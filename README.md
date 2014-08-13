container-builder
=================

Auto building docker image at git pushing.

このツールで作られたリポジトリにプッシュすると、自動的にコンテナイメー
ジが作られコンテナレジストリに登録されます。

https://github.com/naoya/docker-paas-example にインスパイアされて作りました。

依存
-------

* Docker 1.0

動作の概要
----------------

### リポジトリ作成時の動作

1. プッシュ先の Git リポジトリを `~/managed_repos/` ディレクトリに生成
   します。
   リポジトリ名はユニークになるように、連番がつきます。
2. 生成したリポジトリに `pre-receive` フックを生成します。
   pre-receive フックでイメージをビルドするため、ビルドエラーが発生するとプッシュ自体が失敗します。
   このフックには、コンテナのもととなるイメージ名や、アプリケーション名、登録するコンテナレジストリのIPなどが記録されています。
   これらを変更したい場合は、Git リポジトリを作りなおす必要があります。

### プッシュされた時の動作

1. プッシュされると、ベースコンテナイメージをロードして、プッシュされ
   たコミットのソースをチェックアウトします。
   チェックアウト先は、コンテナ内の `/apps/アプリケーション名` にな
   ります。
2. チェックアウトしたコンテナに、 `アプリケーション名_ブランチ名:コミッ
   トID`という名前をつけてイメージを保存します。
3. コンテナを起動して、gem のインストールやアセットのコンパイルをしま
   す。
4. 成功した場合、`コンテナを登録するレジストリアドレス/アプリケーション名_ブランチ名:コミットID`
   を作成します。
5. コンテナレジストリにプッシュします。

使い方
------

`container-builder.rb アプリケーション名` でリポジトリが作られます。
アプリケーションのコンテナのベースのデフォルトは `ubuntu` です。
以下のようにして、ベースコンテナを指定することができます。

```shell
./container-builder.rb sample-app -b other-image
```

ベースコンテナは tar, ruby コマンドが実行できる必要があります。

### Example

```shell
./container-builder.rb sample-app

Repository created!
/your_home/managed_repos/container-0001.git
Add remote and push to it then starting to build.

Add remote ex)
  git remote add container-builder <builder host>:container-0001
or
  git remote add container-builder file:///your_home/managed_repos/container-0001.git

Push it)
  git push container-builder <branch>:<environment>

```

最後の出力にあるように、プッシュ元の Git リポジトリにリモートの設定を
追加します。

```shell
cd sample-app
git remote add container-builder file:///your_home/managed_repos/container-0001.git
```

これで準備が整いました。あとは、ビルドしてほしいブランチをプッシュすれ
ばコンテナがビルドされます。

### プッシュする

```shell
cd sample-app
git push container-builder bugfix/any-bug:staging
```

コンテナ名の命名規則は、`アプリケーション名_ブランチ名:コミットID` で
す。コミットIDはプッシュしたブランチのHEADと同じです。
上記の例だと、`sample-app_staging:e9283a8332` のようになります。

