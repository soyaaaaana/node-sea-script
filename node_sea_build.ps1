# 管理者として実行
if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process -FilePath powershell -ArgumentList "-ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Path)" -Verb runas
    exit
}

# Pause関数の定義
function Pause {
    if ($psISE) {
        $null = Read-Host "$(
        switch ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName) {
            "ja" { "続行するにはEnterキーを押してください" }
            Default { "Press enter key to continue" }
        }). . . "
    }
    else {
        Write-Host -NoNewline "$(
        switch ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName) {
            "ja" { "続行するには何かキーを押してください" }
            Default { "Press any key to continue" }
        }). . . "
        # (Get-Host).UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
        
        do {
            $pause_key = [Console]::ReadKey($true)
        } while (
            # 仮想キーコードが修飾キー（Shift:16, Ctrl:17, Alt:18）かどうか
            ($pause_key.VirtualKeyCode -ge 16 -and $pause_key.VirtualKeyCode -le 18) -or
            # 修飾キー（Control, Alt）が押されている状態を無視
            ($pause_key.Modifiers -ne 0)
        )
        
        Write-Host "`r`n"
    }
}

# スクリプトを終了する関数の定義
function ExitScript {
    Pause
    exit
}

# node.exeを探す
$node_path = where.exe node.exe 2>&1
if ($LASTEXITCODE -eq 1) {
    Write-Host "node.exeが見つかりませんでした。"
    ExitScript
}

if ((Test-Path "$PSScriptRoot\host_node\node.exe")) {
    $node_path = "$PSScriptRoot\host_node\node.exe"
}

# プラットフォームの選択
Write-Host "対象のプラットフォームを選択してください"
Write-Host "[1] Windows"
Write-Host "[2] Linux"
choice /c 12 /n /m "> "
$platform = $LASTEXITCODE

Write-Host ""

if ($platform -eq 2) {
    if (-not (Test-Path "$PSScriptRoot\node\node")) {
        Write-Host "nodeフォルダにnodeが見つかりませんでした。"
        Write-Host "Linux向けにビルドするには、nodeフォルダにnodeバイナリを配置する必要があります。"
        ExitScript
    }
}

# package.jsonの読み込み
$json = '{"main":"main.js"}' | ConvertFrom-Json
if (Test-Path "$PSScriptRoot\package.json") {
    $json = Get-Content -Path "$PSScriptRoot\package.json" -Raw -Encoding UTF8 | ConvertFrom-Json
}

# main(jsファイル)の指定
$count = 0
$main = ""
while ($true) {
    if ($count -ne 0) {
        Write-Host "エラー: 存在しないファイルが選択されました。"
    }

    Write-Host -NoNewline "メインのJavaScriptファイルを指定してください($($json.main)): "
    $main_input = Read-Host

    if ($main_input -eq "") {
        $main = $json.main
    }
    else {
        $main = $main_input
    }

    if (Test-Path "$PSScriptRoot\$main") {
        break
    }

    # 拡張子を省略しても大丈夫
    if (Test-Path "$PSScriptRoot\$main.js") {
        $main = "$main.js"
        break
    }
    $count++
}
Write-Host ""

# esbuildのチェック
Write-Host "esbuildがインストールされているかをチェックしています. . . "
npm ls -g esbuild > $null 2>&1
if ($LASTEXITCODE -eq 1) {
    Write-Host "esbuildをインストールしています. . . "
    npm i esbuild -g
}
else {
    Write-Host "esbuildはインストール済みです。"
}

# buildディレクトリの作成
New-Item "$PSScriptRoot\build" -ItemType Directory -ErrorAction SilentlyContinue

# esbuildでnode_modulesをパックしてMinify化
Write-Host "コードをビルドしています. . . "
esbuild "$PSScriptRoot\$main" --bundle "--outfile=$PSScriptRoot\build\$main" --platform=node --format=cjs --minify

# sea-config.jsonの生成
Write-Host "必要なファイルを作成しています. . . "

# node --build-sea オプションが使えるバージョンかどうかの判定
$current_node_version = [version](& "$node_path" -v).TrimStart("v")
$build_sea_node_verison = [version]"25.5.0"

if ($current_node_version -ge $build_sea_node_verison) { # v25.5.0以上（node --build-seaをサポートしている）
    $name = $json.name
    if (-not $name) {
        # package.jsonにnameの指定がなかった場合に$mainから拡張子を除いたファイル名を取得してそれを名前($name)とする
        $name = $main -replace "\.[^.]+$", ""
    }

    if ($platform -eq 1) {
        $binary_name = "$name.exe"
        if (Test-Path "$PSScriptRoot\node\node.exe") {
            $node_binary_path = "$PSScriptRoot\node\node.exe"
        }
        else {
            $node_binary_path = "$node_path"
        }
    }
    elseif ($platform -eq 2) {
        $binary_name = "$name"
        $node_binary_path = "$PSScriptRoot\node\node"
    }

    New-Item -Force "$PSScriptRoot\build\sea-config.json" -Value "{""main"":""$($PSScriptRoot.Replace("\", "\\"))\\build\\$($main.Replace("\", "\\"))"",""executable"":""$($node_binary_path.Replace("\", "\\"))"",""output"":""$($PSScriptRoot.Replace("\", "\\"))\\build\\$($binary_name.Replace("\", "\\"))"",""disableExperimentalSEAWarning"":true}"
    
    Write-Host "ビルドしています. . . "
    & $node_path --build-sea "$PSScriptRoot\build\sea-config.json"
}
else { # v25.5.0未満
    New-Item -Force "$PSScriptRoot\build\sea-config.json" -Value "{""main"":""$($PSScriptRoot.Replace("\", "\\"))\\build\\$($main.Replace("\", "\\"))"",""output"":""$($PSScriptRoot.Replace("\", "\\"))\\build\\sea-prep.blob"",""disableExperimentalSEAWarning"":true}"
    & $node_path --experimental-sea-config "$PSScriptRoot\build\sea-config.json"

    # 出力先の設定
    $name = $json.name
    if (-not $name) {
        # package.jsonにnameの指定がなかった場合に$mainから拡張子を除いたファイル名を取得してそれを名前($name)とする
        $name = $main -replace "\.[^.]+$", ""
    }

    if ($platform -eq 1) {
        $build_file = "$name.exe"
        if (Test-Path "$PSScriptRoot\node\node.exe") {
            Copy-Item -Path "$PSScriptRoot\node\node.exe" -Destination "$PSScriptRoot\build\$build_file"
        }
        else {
            Copy-Item -Path "$node_path" -Destination "$PSScriptRoot\build\$build_file"
        }
    }
    elseif ($platform -eq 2) {
        $build_file = "$name"
        Copy-Item -Path "$PSScriptRoot\node\node" -Destination "$PSScriptRoot\build\$build_file"
    }

    # Node.jsアプリケーションにコードを埋め込む
    Write-Host "ビルドしています. . . "
    npx postject "$PSScriptRoot\build\$build_file" NODE_SEA_BLOB "$PSScriptRoot\build\sea-prep.blob" --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 --overwrite
}

Write-Host "`r`n操作が完了しました。"

ExitScript