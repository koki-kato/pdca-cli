# pdca-cli

プログラミングスクール向けPDCA日次報告をコマンドラインから送信するツールです。

## インストール

```bash
git clone <リポジトリURL>
cd pdca-cli
bundle install
```

Ruby 3.0以上が必要です。

## セットアップ

初回のみログインが必要です。講師から共有されたAPI URLと、アカウントのメールアドレス・パスワードを入力してください。

```bash
bin/pdca login
```

```
API URL: https://your-app.herokuapp.com
メールアドレス: student@example.com
パスワード: ********

ログイン成功！ (田中太郎 さん)
```

## 使い方

### 学習計画を設定する

最初に学習計画（カリキュラム）を設定します。

```bash
# 対話型で設定
bin/pdca plan setup

# ワンライナーで設定
bin/pdca plan setup --name "Ruby on Rails学習" \
  --categories "HTML/CSS基礎" "Ruby基礎" "Rails入門" "データベース設計"
```

対話型では「カテゴリ名:目安時間」形式で入力できます（例: `Ruby基礎:10`）。

```bash
# 学習計画を確認
bin/pdca plan show

# カテゴリを追加
bin/pdca plan add --name "テスト(RSpec)" --hours 8
```

### 週次目標を設定する

学習計画のカテゴリから選んで週次目標を設定できます。

```bash
# 対話型で設定（学習計画があればカテゴリ選択可能）
bin/pdca goal create

# カテゴリIDを指定して設定
bin/pdca goal create --category_ids 40 41

# 自由入力で設定
bin/pdca goal create --items "Railsルーティング完了" "RSpec基礎"

# 今週の目標を確認
bin/pdca goal current

# 進捗を更新（対話型）
bin/pdca goal update
```

### PDCA報告を作成する

```bash
# 対話型で作成（おすすめ）
bin/pdca report create

# ワンライナーで作成
bin/pdca report create \
  --status green \
  --plan "Railsチュートリアル第8章" \
  --do "セッション管理の実装を完了" \
  --check "テストが全て通った" \
  --action "明日は第9章に進む"
```

### 報告を確認・管理する

```bash
# 今日の報告
bin/pdca report today

# 特定の日の報告
bin/pdca report show --date 2026-03-30

# 報告一覧
bin/pdca report list
bin/pdca report list --month 2026-03

# 報告を更新
bin/pdca report update --date 2026-03-30 \
  --do "追加の作業を実施" \
  --check "理解が深まった"
```

## コマンド一覧

### 認証

| コマンド | 説明 |
|---------|------|
| `pdca login` | ログイン（API URL + メール + パスワード） |
| `pdca logout` | ログアウト |
| `pdca whoami` | ログイン中のユーザー情報 |

### 学習計画

| コマンド | 説明 |
|---------|------|
| `pdca plan show` | 学習計画を表示（進捗付き） |
| `pdca plan setup` | 学習計画を新規作成 |
| `pdca plan add --name NAME` | カテゴリを追加 |

### 週次目標

| コマンド | 説明 |
|---------|------|
| `pdca goal current` | 今週の目標を表示 |
| `pdca goal create` | 週次目標を作成（学習計画から選択 or 自由入力） |
| `pdca goal update` | 進捗率を更新（対話型） |
| `pdca goal list` | 週次目標の一覧 |

### PDCA報告

| コマンド | 説明 |
|---------|------|
| `pdca report create` | 報告作成（対話型 or フラグ指定） |
| `pdca report today` | 今日の報告を表示 |
| `pdca report show --date DATE` | 指定日の報告を表示 |
| `pdca report list` | 報告一覧 |
| `pdca report update --date DATE` | 報告を更新 |

## オプション

全コマンド共通:
- `--json` : JSON形式で出力（AI連携用）

## 設定

設定ファイル: `~/.pdca.yml`

環境変数で上書き可能:
- `PDCA_API_URL` : API URL
- `PDCA_TOKEN` : 認証トークン

## learning_status（学習状況）の値

| 値 | 意味 |
|---|------|
| `green` | 順調、問題なし |
| `yellow` | 少し詰まっているが対処できそう |
| `red` | 完全に止まっている |
