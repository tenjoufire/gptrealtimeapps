# CopilotSkillsDemoDemo

Azure / GitHub ワークショップ作成を支援する **GitHub Copilot Agent Skills** を提供するリポジトリです。

## 📦 含まれる Agent Skills

| スキル名 | ディレクトリ | 説明 |
|----------|-------------|------|
| Azure IaC Architect | `.github/skills/azure-iac-architect/` | アプリケーションに最適な Azure 環境をヒアリングし、CAF/WAF に基づいた IaC（Bicep/Terraform）を生成 |
| Workshop Planner | `.github/skills/workshop-planner/` | ワークショップ全体の企画・設計（テーマ選定、アジェンダ作成、事前準備チェックリスト等） |
| Hands-on Lab Creator | `.github/skills/hands-on-lab-creator/` | ハンズオンラボの演習手順書を作成（ステップバイステップ手順、チェックポイント、エラー対処等） |
| Workshop README Generator | `.github/skills/workshop-readme-generator/` | ワークショップリポジトリ用のドキュメント一式を生成（README、セットアップガイド、講師ガイド等） |

## 🚀 使い方

### このリポジトリで使う場合
1. Copilot coding agent、GitHub Copilot CLI、または VS Code のエージェントモードでタスクを依頼する
2. Copilot がタスクに応じて関連するスキルを自動的に読み込み、専門的な指示に従って作業を行います

### 他のリポジトリで使う場合（再配布）
1. `.github/skills/` ディレクトリ内の各スキルフォルダ（`SKILL.md` を含む）をコピー
2. 対象リポジトリの `.github/skills/` に配置
3. そのリポジトリで Copilot Agent が自動的にスキルを利用可能になります

> 📖 詳細は [Creating agent skills for GitHub Copilot](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-skills) を参照してください。

## 💡 使用例

### Azure IaC を設計・生成する
> Azure OpenAI を使った Python FastAPI アプリを Azure にデプロイしたいです。IaC を設計・生成してください。

### ワークショップを企画する
> Azure OpenAI と GitHub Copilot を活用した AI アプリ開発の半日ワークショップを企画してください。対象者は Web 開発経験のあるエンジニアです。

### ハンズオンラボを作成する
> GitHub Actions で Azure App Service にデプロイする CI/CD パイプライン構築のハンズオンラボを作成してください。難易度は初級でお願いします。

### ドキュメントを生成する
> このワークショップリポジトリの README とセットアップガイドを生成してください。
