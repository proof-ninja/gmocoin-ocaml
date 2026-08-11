(lang dune 3.4)

(name gmocoin)

(version dev)

(generate_opam_files true)

(source
 (github proof-ninja/gmocoin-ocaml))

(authors "Yoshihiro Imai")

(maintainers "Yoshihiro Imai")

(license MIT)

(documentation https://github.com/proof-ninja/gmocoin-ocaml/)

(package
 (name gmocoin)
 (synopsis "OCaml client for the GMO Coin cryptocurrency exchange API")
 (description
  "Provides typed bindings to GMO Coin's public and private HTTP APIs (market data, order placement and management, positions, assets, margin, account transfers) and both the public and private realtime WebSocket APIs (ticker, orderbook, trades, and authenticated execution/order/position event channels). Handles HMAC-SHA256 request signing and rate limiting automatically.")
 (depends ocaml dune cohttp lwt cohttp-lwt-unix yojson ppx_deriving_yojson hacl-star hex dolog lwt_ppx websocket-lwt-unix ipaddr (alcotest :with-test))
 (tags
  ("cryptocurrency" "exchange" "trading" "api" "websocket")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
