# LLMライブラリ互換性調査

2026-09-21、Moon 0.1.20260920、native、moonbitlang/async 0.22.1で調査。
結論は現在の `src/openai` を維持する。候補を本体の依存には追加していない。

追記(2026-09-22): 同日に `src/openai` の中身を自作の `gaato/openai`(mbt-sdk)に置き換えた。HTTP ステータス付きのエラー、429 の再試行、`FakeTransport` による通信なしのテストが、この調査で候補に欠けていた点をそのまま埋める。

## 比較結果

| 項目 | mizchi/llm 0.3.2 | marianoguerra/llm 0.3.0 |
|---|---|---|
| native + async 0.22.1 | コンパイル失敗 | ローカルHTTPテスト成功 |
| 接続先変更 | `base_url`がある（ソース確認） | `HttpTransport.url`で任意の完全URLを指定できる（実測） |
| 非streaming応答 | `collect_text`がある（ソース確認） | transportとdialectを組み合わせて取得・解析できる（実測） |
| reasoning設定 | 公開constructorとリクエスト生成に設定がない | gpt-5.6でnone/low/medium/high/xhigh/maxすべて一致（実測） |
| HTTPエラー | 非2xxは空文字になる（ソース確認） | 本文は維持するがHTTPステータスを捨てる（実測・ソース確認） |
| JSON応答の異常 | JSON破損・choicesなし・contentなしも空文字（ソース確認） | transportはそのまま本文を渡す。JSON解析とdialectの処理が別に必要 |
| 接続解放 | HTTP実装に`defer client.close()`がある。ビルド失敗のため実行未確認 | asyncのone-shot HTTP処理に`defer client.close()`がある。リーク測定は未実施 |

## 根拠と判断

### mizchi/llm

[公開パッケージ](https://mooncakes.io/docs/mizchi/llm@0.3.2)を取得し、
async 0.22.1を直接依存に指定した一時モジュールからOpenAIパッケージをimportした。
推移依存の `mizchi/x@0.5.3` の `src/http/http_native.mbt` で、
`Map[String, String]` と `Map[CaseInsensitiveString, String]` の不一致、
`CaseInsensitiveString.to_lower` の不存在によりコンパイルに失敗した。
したがって用意したHTTP fixtureは実行に至っていない。

`src/openai/openai_x_async.mbt` の `collect_text` は通信・非2xx・解析失敗を
空文字へ変換する。`build_openai_body_nonstream`にはreasoning設定がない。
`src/ffi/x_async.mbt`ではtimeout引数も利用されていない。
依存互換とエラー契約の両方に変更が必要なため、現時点では採用しない。

### marianoguerra/llm

[公開パッケージ](https://mooncakes.io/docs/marianoguerra/llm@0.3.0)を同じasyncバージョンで検証。
2テストが成功した。1つはreasoning設定6種類のJSON生成、もう1つはlocalhost上の
HTTPサーバーによる200正常JSON・429エラーJSON・200不正JSONの3ケース。
任意URLへのPOST、応答本文、完了callback、正常応答とAPIエラーのdialect解析を確認した。

`wire/transport.mbt`は `ignore(resp.code)` として本文をcallbackへ渡す。
429でもtransportのerror callbackは呼ばれず、dialectがJSON内のエラーを解釈する。
Nekosamaの `OpenAIError::Http(status, body)` を保つには独自transportが必要となる。
モデル情報に応じてreasoning設定を調整する仕組みもあるため、gpt-5.6以外については
現在の「指定値をそのまま送る」動作との互換性を別途確認する必要がある。
採用する場合の有力候補だが、115行の現クライアントを置換する利点はまだ小さい。

## 検証環境と再確認

一時モジュールとHTTP fixtureは以下に保存した。認証情報はダミー値のみ。
外部LLM APIへの送信は行っていない。

- `/tmp/nekosama-llm-audit/mizchi`
- `/tmp/nekosama-llm-audit/marianoguerra`

各ディレクトリで `moon test --target native` を実行する。
ローカルHTTPテストにはlocalhostソケットの作成権限が必要。
依存パッケージのソースは変更していない。
接続解放はソース確認であり、キャンセル・タイムアウトや実APIでの挙動は未検証。

## 同時に行った日時処理整理

`moonbitlang/x@0.5.5` の `time` を使い、暦計算とJST変換を置換した。
入力パーサーとISO出力は維持。ライブラリが許可する24:00は従来どおり拒否する。
ライブラリの日付範囲は-9999～9999年で、4桁の明示入力は範囲内。
現在時刻に9999年末を注入して年なし入力を10000年へ繰り上げるケースは範囲外となる。

| 行数分類 | 変更前 | 変更後 | 増減 |
|---|---:|---:|---:|
| 日時処理本体 | 203 | 154 | -49 |
| 日時テスト | 82 | 89 | +7 |
| 依存定義 | — | — | +2 |
| 生成インターフェース | — | — | 0 |

本体から別の自作パッケージへ移動した行は0行。調査文書を除く差分は合計-40行。
native check、70テスト、release build、fmt、infoを完了した。
