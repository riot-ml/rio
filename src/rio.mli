module Iovec : sig
  type iov = { ba : bytes; off : int; len : int }
  type t = iov array

  val with_capacity : int -> t
  val create : ?count:int -> size:int -> unit -> t
  val sub : ?pos:int -> len:int -> t -> t
  val length : t -> int
  val iter : t -> (iov -> unit) -> unit
  val of_bytes : bytes -> t
  val from_string : string -> t
  val from_buffer : Buffer.t -> t
  val into_string : t -> string
end

module type Write = sig
  type t
  type error

  val write : t -> buf:string -> (int, error) result
  val write_owned_vectored : t -> bufs:Iovec.t -> (int, error) result
  val flush : t -> (unit, error) result
end

module Writer : sig
  type ('src, 'err) write =
    (module Write with type t = 'src and type error = 'err)

  type ('src, 'err) t

  val of_write_src : ('src, 'err) write -> 'src -> ('src, 'err) t
end

module type Read = sig
  type t
  type error

  val read : t -> ?timeout:int64 -> bytes -> (int, error) result
  val read_vectored : t -> Iovec.t -> (int, error) result
end

module Reader : sig
  type ('src, 'err) read =
    (module Read with type t = 'src and type error = 'err)

  type ('src, 'err) t

  val of_read_src : ('src, 'err) read -> 'src -> ('src, 'err) t
  val empty : (unit, unit) t
end

val read : ('a, 'err) Reader.t -> ?timeout:int64 -> bytes -> (int, 'err) result
val read_vectored : ('a, 'err) Reader.t -> Iovec.t -> (int, 'err) result
val read_to_end : ('a, 'err) Reader.t -> buf:Buffer.t -> (int, 'err) result
val write : ('src, 'err) Writer.t -> buf:string -> (int, 'err) result
val write_all : ('a, 'err) Writer.t -> buf:string -> (unit, 'err) result

val write_owned_vectored :
  ('a, 'err) Writer.t -> bufs:Iovec.t -> (int, 'err) result

val write_all_vectored :
  ('a, 'err) Writer.t -> bufs:Iovec.t -> (unit, 'err) result

val flush : ('a, 'err) Writer.t -> (unit, 'err) result

module Bytes : sig
  type t = bytes

  val empty : t
  val with_capacity : int -> t
  val length : t -> int
  val sub : t -> pos:int -> len:int -> t
  val of_string : string -> t
  val to_string : t -> string
  val split : ?max:int -> on:string -> t -> t list
  val join : t -> t -> t

  module Bytes_writer : sig
    type t
  end

  val to_writer : t -> (Bytes_writer.t, exn) Writer.t
end

module Buffer : sig
  type t = Buffer.t

  val with_capacity : int -> t
  val length : t -> int
  val contents : t -> string
  val to_bytes : t -> bytes
  val to_writer : t -> (t, exn) Writer.t
end
