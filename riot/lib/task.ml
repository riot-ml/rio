open Runtime

module Logger = Logger.Make (struct
  let namespace = [ "riot"; "task" ]
end)

type 'a t = { pid : Pid.t; ref : 'a Ref.t }
type Message.t += Reply : 'a Ref.t * 'a -> Message.t

let async fn =
  let ref = Ref.make () in
  let this = self () in
  let pid =
    spawn (fun () ->
        Logger.trace (fun f -> f "spawned task %a" Pid.pp (self ()));
        let value = fn () in
        let reply = Reply (ref, value) in
        Logger.trace (fun f -> f "sending message back: %a" Pid.pp (self ()));
        send this reply)
  in
  monitor this pid;
  { pid; ref }

let await :
    type res.
    ?timeout:int64 -> res t -> (res, [> `Timeout | `Process_down ]) result =
 fun ?timeout:after t ->
  Logger.trace (fun f ->
      f "Process %a is awaing for task %a with timeout %Ld" Pid.pp (self ())
        Pid.pp t.pid
        (Option.value ~default:(-1L) after));
  match[@warning "-8"] receive ?after () with
  | exception Receive_timeout -> Error `Timeout
  | Reply (ref', res) when Ref.equal t.ref ref' -> (
      Process.demonitor t.pid;
      match Ref.type_equal t.ref ref' with
      | Some Type.Equal -> Ok res
      | None -> failwith "bad message")
  | Process.Messages.Monitor (Process_down pid) when Pid.equal pid t.pid ->
      Error `Process_down