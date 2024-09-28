let ( let* ) = Result.bind

type io_error =
  [ `Connection_closed
  | `Exn of exn
  | `No_info
  | `Unix_error of Unix.error
  | `Noop
  | `Eof
  | `Closed
  | `Process_down
  | `Timeout
  | `Would_block ]

type ('ok, 'err) io_result = ('ok, ([> io_error ] as 'err)) Stdlib.result

let pp_err fmt = function
  | `Noop -> Format.fprintf fmt "Noop"
  | `Eof -> Format.fprintf fmt "End of file"
  | `Timeout -> Format.fprintf fmt "Timeout"
  | `Process_down -> Format.fprintf fmt "Process_down"
  | `System_limit -> Format.fprintf fmt "System_limit"
  | `Closed -> Format.fprintf fmt "Closed"
  | `Connection_closed -> Format.fprintf fmt "Connection closed"
  | `Exn exn ->
      Format.fprintf fmt "Unexpected exceptoin: %s" (Printexc.to_string exn)
  | `No_info -> Format.fprintf fmt "No info"
  | `Would_block -> Format.fprintf fmt "Would block"
  | `Unix_error err ->
      Format.fprintf fmt "Unix_error(%s)" (Unix.error_message err)

module Iovec = struct
  type iov = { ba : bytes; off : int; len : int }
  type t = iov array

  (** creates an iovector array with [size] equally distributed in [count]s *)
  let create ?(count = 1) ~size () =
    assert (count > 0);
    assert (size > 0);
    let size = size / count in
    Array.init count (fun _id ->
        { ba = Bytes.create size; off = 0; len = size })

  let with_capacity size = create ~size ()

  let sub ?(pos = 0) ~len t =
    let curr = ref 0 in
    t |> Array.to_list
    |> List.filter_map (fun iov ->
           if !curr + iov.len < pos then (
             curr := !curr + iov.len;
             None)
           else
             let next_curr = iov.len + !curr in
             let diff = len - !curr in
             if next_curr < len then (
               curr := next_curr;
               Some iov)
             else if diff > 0 then (
               curr := len;
               Some { iov with len = diff })
             else None)
    |> Array.of_list

  let length t = Array.fold_left (fun acc iov -> acc + (iov.len - iov.off)) 0 t
  let iter (t : t) fn = Array.iter fn t
  let of_bytes ba = [| { ba; off = 0; len = Bytes.length ba } |]

  let from_string str = of_bytes (Bytes.of_string str)
  let from_buffer buf = of_bytes (Buffer.to_bytes buf)

  let into_string t =
    let buf = Buffer.create (length t) in
    iter t (fun iov -> Buffer.add_bytes buf (Bytes.sub iov.ba iov.off iov.len));
    Buffer.contents buf
end

module type Write = sig
  type t

  val write : t -> buf:string -> (int, [> `Closed ]) io_result
  val write_owned_vectored : t -> bufs:Iovec.t -> (int, [> `Closed ]) io_result
  val flush : t -> (unit, [> `Closed ]) io_result
end

module Writer = struct
  type 'src write = (module Write with type t = 'src)
  type 'src t = Writer of ('src write * 'src)

  let of_write_src : type src. src write -> src -> src t =
   fun write src -> Writer (write, src)

  let write : type src. src t -> buf:string -> (int, [> `Closed ]) io_result =
   fun (Writer ((module W), dst)) ~buf -> W.write dst ~buf

  let write_owned_vectored :
      type src. src t -> bufs:Iovec.t -> (int, [> `Closed ]) io_result =
   fun (Writer ((module W), dst)) ~bufs -> W.write_owned_vectored dst ~bufs

  let flush : type src. src t -> (unit, [> `Closed ]) io_result =
   fun (Writer ((module W), dst)) -> W.flush dst

  let write_all :
      type src. src t -> buf:string -> (unit, [> `Closed ]) io_result =
   fun (Writer ((module W), dst)) ~buf ->
    let total = String.length buf in
    let rec write_loop buf len =
      if String.length buf > 0 then
        let* n = W.write dst ~buf in
        let rest = len - n in
        write_loop (String.sub buf n (len - n)) rest
      else Ok ()
    in
    write_loop buf total

  let write_all_vectored :
      type src. src t -> bufs:Iovec.t -> (unit, [> `Closed ]) io_result =
   fun (Writer ((module W), dst)) ~bufs ->
    let total = Iovec.length bufs in
    let rec write_loop bufs len =
      if Iovec.length bufs > 0 then
        let* n = W.write_owned_vectored dst ~bufs in
        let rest = len - n in
        write_loop (Iovec.sub bufs ~pos:n ~len:(len - n)) rest
      else Ok ()
    in
    write_loop bufs total
end

module type Read = sig
  type t

  val read : t -> ?timeout:int64 -> bytes -> (int, [> `Closed ]) io_result
  val read_vectored : t -> Iovec.t -> (int, [> `Closed ]) io_result
end

module Reader = struct
  type 'src read = (module Read with type t = 'src)
  type 'src t = Reader of ('src read * 'src)

  let of_read_src : type src. src read -> src -> src t =
   fun read src -> Reader (read, src)

  let read :
      type src dst.
      src t -> ?timeout:int64 -> bytes -> (int, [> `Closed ]) io_result =
   fun (Reader ((module R), src)) ?timeout buf -> R.read src ?timeout buf

  let read_vectored :
      type src dst. src t -> Iovec.t -> (int, [> `Closed ]) io_result =
   fun (Reader ((module R), src)) bufs -> R.read_vectored src bufs

  let read_to_end :
      type src dst. src t -> buf:Buffer.t -> (int, [> `Closed ]) io_result =
   fun (Reader ((module R), src)) ~buf:out ->
    let buf = Bytes.create 1024 in
    let rec read_loop total =
      match R.read src buf with
      | Ok 0 -> Ok total
      | Ok len ->
          Buffer.add_bytes out (Bytes.sub buf 0 len);
          read_loop (len + total)
      | Error err -> Error err
    in
    read_loop 0

  let empty =
    let module EmptyRead = struct
      type t = unit

      let read () ?timeout:_ _buf = Ok 0
      let read_vectored () _bufs = Ok 0
    end in
    of_read_src (module EmptyRead) ()
end

let read = Reader.read
let read_to_end = Reader.read_to_end
let read_vectored = Reader.read_vectored
let write = Writer.write
let write_all = Writer.write_all
let write_all_vectored = Writer.write_all_vectored
let write_owned_vectored = Writer.write_owned_vectored
let flush = Writer.flush

module Bytes = struct
  include BytesLabels

  let with_capacity size = make size '\000'
  let empty = with_capacity 0
  let join = cat

  let split ?(max = 1) ~on t =
    let splits = ref [] in
    let window_size = String.length on in
    let current = ref t in
    let filled = length t in
    let exception Done in
    try
      let last_off = ref 0 in
      for _ = 0 to filled - 1 - window_size do
        let off = !last_off in
        let window =
          if off + window_size < length !current then
            sub ~pos:off ~len:window_size !current
          else (
            (* save everything up to the window *)
            splits := !current :: !splits;
            raise_notrace Done)
        in
        let win_str = to_string window in
        let matches = String.equal win_str on in
        (* if we find the window is exactly what we're searching for, we have a
           split point *)
        if matches then (
          let split = sub ~pos:0 ~len:off !current in
          (* save everything up to the window *)
          splits := split :: !splits;
          (* move our current to after the window *)
          let rest =
            sub ~pos:(off + window_size)
              ~len:(filled - off - window_size)
              !current
          in
          if List.length !splits = max then (
            splits := rest :: !splits;
            raise_notrace Done);
          current := rest;
          last_off := 0)
        else last_off := off + 1
      done;
      !splits |> List.rev
    with Done -> !splits |> List.rev

  module Bytes_writer = struct
    type t = bytes

    let write t ~buf =
      let buf = Bytes.unsafe_of_string buf in
      let len = Bytes.length buf in
      blit ~src:buf ~src_pos:0 ~dst:t ~dst_pos:0 ~len;
      Ok len

    let write_owned_vectored t ~bufs =
      let iov = Iovec.sub bufs ~len:(length t) in
      let pos = ref 0 in
      Iovec.iter bufs (fun iov ->
          if iov.len < 0 then failwith "iov.len < 0";
          if iov.off < 0 then failwith "iov.off < 0";
          if !pos < 0 then failwith "!pos < 0";
          if iov.off > length iov.ba - iov.len then
            failwith "iov.off > length iov.ba - iov.len";
          if !pos > length t - iov.len then
            failwith
              (Format.sprintf "!pos (%d) > length t (%d) - iov.len (%d)" !pos
                 (length t) iov.len);
          blit ~src:iov.ba ~src_pos:iov.off ~len:iov.len ~dst:t ~dst_pos:!pos;
          pos := !pos + iov.len);
      Ok (Iovec.length iov)

    let flush _t = Ok ()
  end

  let to_writer t = Writer.of_write_src (module Bytes_writer) t
end

module Buffer = struct
  include Buffer

  let with_capacity size = create size

  module Buffer_writer = struct
    type t = Buffer.t

    let write t ~buf =
      let buf = Bytes.unsafe_of_string buf in
      Buffer.add_bytes t buf;
      Ok (Bytes.length buf)

    let write_owned_vectored t ~bufs =
      Iovec.iter bufs (fun iov ->
          Buffer.add_bytes t (Bytes.sub iov.ba ~pos:iov.off ~len:iov.len));
      Ok (Iovec.length bufs)

    let flush _t = Ok ()
  end

  let to_writer t = Writer.of_write_src (module Buffer_writer) t
end
