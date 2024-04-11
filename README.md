<h1 align="center">
  Rio
</h1>

<p align="center">
  Ergonomic, composable, efficient read/write streams
</p>

Rio is the composable streaming I/O layer on which Riot is built on. It
provides the interfaces to define Readers and Writers for customs sources and
sinks, and it provides functions to glue them together.

It is heavily inspired by Rust's Read and Write traits.

It also provides common instances of Read/Write for Buffer, Bytes, and
Cstruct.

## The Read interface

The Read interface defines how to read bytes from a source. 

Implementors of this interface are called 'readers'.

Reader are meant to compose nicely with each other.

Note that each call to `Rio.read reader` may involve a system call.

## The Write interface

The Write interface defines objects that are byte-oriented sinks.

Implementors of this interface are called 'writers'.

Writers are meant to compose nicely with each other.
