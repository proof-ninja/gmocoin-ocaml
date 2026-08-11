(lang dune 3.4)

(name gmocoin)

(version dev)

(generate_opam_files true)

(source
 (github proof-ninja/gmocoin-ocaml))

(authors "Yoshihiro Imai")

(maintainers "Yoshihiro Imai")

(license MIT)

(documentation https://url/to/documentation)

(package
 (name gmocoin)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends ocaml dune cohttp lwt cohttp-lwt-unix yojson ppx_deriving_yojson hacl-star hex dolog lwt_ppx websocket-lwt-unix ipaddr (alcotest :with-test))
 (tags
  (topics "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
