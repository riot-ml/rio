(lang dune 3.11)
(using melange 0.1)
(using mdx 0.4)

(name rio)

(generate_opam_files true)

(source
 (github riot-ml/rio))

(authors "Leandro Ostera <leandro@abstractmachines.dev>")

(maintainers "Leandro Ostera <leandro@abstractmachines.dev>")

(license MIT)

(package
  (name rio)
  (synopsis "Ergonomic, composable, efficient read/write streams")
  (description
    "Rio implements ergonomic, composable, efficient read/write streams that give you a uniform interface for reading from any source and writing to any sync.")
  (depends ocaml dune)
  (tags (multicore io streams read write)))
