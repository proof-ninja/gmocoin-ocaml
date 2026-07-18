# GMOコイン API from OCaml

[![Builds, tests & co](https://github.com/proof-ninja/gmocoin-ocaml/actions/workflows/ocaml-ci.yml/badge.svg)](https://github.com/proof-ninja/gmocoin-ocaml/actions/workflows/ocaml-ci.yml)

[GMOコイン 暗号資産取引所API](https://api.coin.z.com/docs/#outline) のOCaml SDKです。

## セットアップ

Private APIを使うには、カレントディレクトリに `gmocoin-auth.conf` を作成し、1行目にAPIキー、2行目にAPIシークレットを書いてください。

```
YOUR_API_KEY
YOUR_API_SECRET
```

```ocaml
open Gmocoin

let () =
  let auth = Auth.auth () in
  Lwt_main.run begin
    PrivateApi.assets auth () >>= fun assets ->
    ...
  end
```

## 実装上の注意

- **TLSバックエンド**: `api.coin.z.com` はcohttp-lwt-unixの既定TLSバックエンド (ocaml-tls, "native") で接続すると、ハンドシェイク後や応答読み取り中に断続的に`ECONNRESET`/`EPIPE`で切断されることを確認しています(WAF等によるTLSフィンガープリント判定と見られます)。`lib/http.ml`でプロセス起動時に`CONDUIT_TLS=openssl`環境変数を自動設定してOpenSSLバックエンドを強制していますが、これでも完全には解消しないため、`Http.get`(冪等なGETのみ)は該当エラーを検知すると最大5回まで自動リトライします。`POST`は二重注文を避けるため意図的にリトライしません。
- **署名対象パス**: GMOコインの署名は `/v1/...` (`/private`を含まない、クエリ文字列も含まない) を対象にHMAC-SHA256で計算します。実際のリクエストURLには`/private`を付与しますが、署名にはそのまま使わないよう`ApiCommon`内で分離しています。
- **レスポンスエンベロープ**: 全レスポンスは `{"status": 0, "data": ..., "responsetime": "..."}` という共通形式です。`status`が0以外の場合、型付きの`{status: int; messages: {message_code; message_string} list}`を積んだ`ApiCommon.Api_error`を投げます。ただし`PublicApi.status`だけは例外にせず`(string, ApiCommon.api_error) result Lwt.t`を返します(取引所稼働状況の確認自体がメンテナンス中に例外で失敗するのは本末転倒なため)。
- **数値の文字列表現**: price/sizeなど大半の数値フィールドはJSON上で文字列 (`"455659"`) として返されるため、型定義でも`string`としています。呼び出し側で必要に応じて`float_of_string`等に変換してください。

## テスト

```
dune test
```

`test/test_gmocoin.ml`にJSONパース(公式ドキュメントのレスポンス例をそのまま使用、MARKET注文で`price`が欠落するケースやCANCELED注文で`cancelType`が付くケースなどoptionフィールドの境界も含む)と`RateLimiter`のスライディングウィンドウ挙動を検証する単体テスト([alcotest](https://github.com/mirage/alcotest))があります。ネットワークアクセスは行いません。

## レートリミッター

[API制限](https://api.coin.z.com/docs/#outline)に基づき、`ApiCommon`がPrivate APIの全リクエストに自動で流量制限をかけます(`RateLimiter`モジュール、スライディングウィンドウ方式)。上限に達した場合は例外を投げずに、枠が空くまで自動的に待機してから送信します。

| 対象 | 上限 | 備考 |
|---|---|---|
| Private API GET | 20回/秒 | Tier 1 (先週の取引高 < 10億円) を既定値として採用。Tier 2 (30回/秒) は未対応 |
| Private API POST | 20回/秒 | 同上 |
| Public API | 制限なし | ドキュメントに具体的な数値の記載なし |

Public WebSocket / Private WebSocketの「subscribe/unsubscribeは1秒間1回まで」という制限は、WebSocket API自体が未実装のため未対応です。

## API実装状況

### Public API

ベースURL: `https://api.coin.z.com/public`

| API | エンドポイント | 状態 | 実装 |
|---|---|---|---|
| 取引所ステータス | `GET /v1/status` | ✅ | `PublicApi.status` |
| 最新レート | `GET /v1/ticker` | ✅ | `PublicApi.ticker` |
| 板情報 | `GET /v1/orderbooks` | ✅ | `PublicApi.orderbooks` |
| 取引履歴 | `GET /v1/trades` | ✅ | `PublicApi.trades` |
| KLine情報の取得 | `GET /v1/klines` | ✅ | `PublicApi.klines` |
| 取引ルール | `GET /v1/symbols` | ✅ | `PublicApi.symbols` |

### Public WebSocket API

エンドポイント: `wss://api.coin.z.com/ws/public`

| チャンネル | 状態 | 実装 |
|---|---|---|
| 最新レート (ticker) | ❌ | - |
| 板情報 (orderbooks) | ❌ | - |
| 取引履歴 (trades) | ❌ | - |

### Private API

ベースURL: `https://api.coin.z.com/private`。すべて認証が必要です。

| API | エンドポイント | 状態 | 実装 |
|---|---|---|---|
| 余力情報を取得 | `GET /v1/account/margin` | ✅ | `PrivateApi.margin` |
| 資産残高を取得 | `GET /v1/account/assets` | ✅ | `PrivateApi.assets` |
| 取引高情報を取得 | `GET /v1/account/tradingVolume` | ❌ | - |
| 日本円の入金履歴の取得 | `GET /v1/account/fiatDeposit/history` | ❌ | - |
| 日本円の出金履歴の取得 | `GET /v1/account/fiatWithdrawal/history` | ❌ | - |
| 暗号資産の預入履歴の取得 | `GET /v1/account/deposit/history` | ❌ | - |
| 暗号資産の送付履歴の取得 | `GET /v1/account/withdrawal/history` | ❌ | - |
| 注文情報取得 | `GET /v1/orders` | ✅ | `PrivateApi.orders` |
| 有効注文一覧 | `GET /v1/activeOrders` | ✅ | `PrivateApi.active_orders` |
| 約定情報取得 | `GET /v1/executions` | ✅ | `PrivateApi.executions` |
| 最新の約定一覧 | `GET /v1/latestExecutions` | ✅ | `PrivateApi.latest_executions` |
| 建玉一覧を取得 | `GET /v1/openPositions` | ✅ | `PrivateApi.open_positions` |
| 建玉サマリーを取得 | `GET /v1/positionSummary` | ✅ | `PrivateApi.position_summary` |
| 口座振替 | `POST /v1/account/transfer` | ❌ | - |
| 注文 | `POST /v1/order` | ✅ | `PrivateApi.order` |
| 注文変更 | `POST /v1/changeOrder` | ❌ | - |
| 注文キャンセル | `POST /v1/cancelOrder` | ✅ | `PrivateApi.cancel_order` |
| 注文の複数キャンセル | `POST /v1/cancelOrders` | ❌ | - |
| 注文の一括キャンセル | `POST /v1/cancelBulkOrder` | ❌ | - |
| 決済注文 | `POST /v1/closeOrder` | ❌ | - |
| 一括決済注文 | `POST /v1/closeBulkOrder` | ❌ | - |
| ロスカットレート変更 | `POST /v1/changeLosscutPrice` | ❌ | - |
| アクセストークンを取得/延長/削除 | `POST`/`PUT`/`DELETE /v1/ws-auth` | ❌ | Private WebSocket用。WebSocket本体が未実装のため対応後回し |

### Private WebSocket API

エンドポイント: `wss://api.coin.z.com/ws/private`

| チャンネル | 状態 | 実装 |
|---|---|---|
| 約定情報通知 | ❌ | - |
| 注文情報通知 | ❌ | - |
| ポジション情報通知 | ❌ | - |
| ポジションサマリー情報通知 | ❌ | - |
