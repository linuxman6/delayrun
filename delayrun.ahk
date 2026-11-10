#Requires AutoHotkey v2.0
#SingleInstance Force

; 設定ファイルの保存先
global iniPath := A_ScriptDir "\delayrun.ini"
global appList := []
global minGuiW := 600  ; 最小ウィンドウ幅
global minGuiH := 380  ; 最小ウィンドウ高さ
global isAutoRun := false ; /run オプションで起動されたかどうかのフラグ

; 連続実行の非同期制御用変数
global isRunning := false
global currentRunIndex := 0
global currentRemainSec := 0

; GUIの作成（サイズ変更可能にする）
myGui := Gui("+Resize", "アプリ連続起動ツール Pro")

; --- ダークモードのカラー設定 ---
myGui.BackColor := "1E1E1E" ; 画面全体の背景（ダークグレー）

; ボタンやテキストの文字色を「眩しくない暗めの白（薄いグレー: B0B0B0）」に設定
myGui.SetFont("s10 cB0B0B0", "Segoe UI")

; 操作ボタンエリア（重なりを解消し、間隔を5pxに均一化）
btnAdd  := myGui.Add("Button", "x10 y10 w70", "➕ 追加")
btnEdit := myGui.Add("Button", "x85 y10 w100", "✏️ 秒数変更")
btnDel  := myGui.Add("Button", "x190 y10 w70", "❌ 削除")
btnUp   := myGui.Add("Button", "x265 y10 w35", "🔼")
btnDown := myGui.Add("Button", "x305 y10 w35", "🔽")
btnTest := myGui.Add("Button", "x345 y10 w100", "⚡ テスト実行")
btnRun  := myGui.Add("Button", "x450 y10 w110", "▶️ 連続実行")

; エラー処理の設定（暗めの白文字）
myGui.Add("Text", "x10 y45 w120 h20 cB0B0B0", "⚠️ 起動失敗時：")
radStop := myGui.Add("Radio", "x130 y43 w110 h20 Group Checked cB0B0B0", "処理を停止")
radSkip := myGui.Add("Radio", "x245 y43 w150 h20 cB0B0B0", "無視して次に進む")

; カウントダウン表示用ラベル
myGui.SetFont("bold s11 c4A90E2")
txtStatus := myGui.Add("Text", "x400 y44 w180 h20", "")
myGui.SetFont("norm s10 cB0B0B0")

; リスト表示エリア（背景を少し暗くし、文字色を暗めの白に設定）
lv := myGui.Add("ListView", "x10 y75 w560 h260 Grid -Multi Checked Background1C1C1C cB0B0B0", ["順番", "管理者", "待機秒数", "ファイル／フォルダ／URL"])
lv.ModifyCol(1, 50)
lv.ModifyCol(2, 60)
lv.ModifyCol(3, 80)
lv.ModifyCol(4, 350)

; WindowsのテーマAPIを使ってリストビューの枠線とヘッダーをダークモードに変更
DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

; イベント登録
btnAdd.OnEvent("Click", AddTargetMenu)
btnEdit.OnEvent("Click", EditDelay)
btnDel.OnEvent("Click", DeleteApp)
btnUp.OnEvent("Click", MoveUp)
btnDown.OnEvent("Click", MoveDown)
btnTest.OnEvent("Click", TestCurrentApp)
btnRun.OnEvent("Click", ToggleRunApps)
radStop.OnEvent("Click", SaveErrorSetting)
radSkip.OnEvent("Click", SaveErrorSetting)
lv.OnEvent("DoubleClick", EditDelay)
lv.OnEvent("ItemCheck", (*) => UpdateAndSave())
myGui.OnEvent("Size", GuiSizeChange)
myGui.OnEvent("DropFiles", Gui_DropFiles) ; ドラッグ＆ドロップイベント
myGui.OnEvent("Close", (*) => ExitApp())

; 起動時に設定を読み込み
LoadSettings()

; 初期表示サイズを指定して表示
myGui.Show("w" minGuiW " h" minGuiH)

; コマンドライン引数のチェック
if (A_Args.Length > 0) {
    for arg in A_Args {
        if (StrLower(arg) == "/run" || StrLower(arg) == "-run") {
            global isAutoRun := true
            SetTimer(ToggleRunApps, -500) ; 自動実行スタート
            break
        }
    }
}
; --- 各種関数 ---

; ウィンドウサイズが変更されたときに自動調整する
GuiSizeChange(thisGui, windowMinMax, width, height) {
    if (windowMinMax = -1)
        return
    w := (width < minGuiW) ? minGuiW : width
    h := (height < minGuiH) ? minGuiH : height
    lv.Move(, , w - 20, h - 90)
    txtStatus.Move(, , w - 410)
}

; ドラッグ＆ドロップでファイルやフォルダを追加する
Gui_DropFiles(thisGui, ctrl, fileArray, x, y) {
    for filePath in fileArray {
        nextRow := lv.GetCount() + 1
        lv.Add(, nextRow, "", "0 秒", filePath)
    }
    UpdateAndSave()
}

; 画面のリストビューと内部配列を同期して保存する
UpdateAndSave() {
    global appList := []
    Loop lv.GetCount() {
        lv.Modify(A_Index, "Col1", A_Index)
        
        ; 【完全修正】AHK v2のListViewで確実にチェックを取得する元のロジックに復元
        isAdmin := (lv.GetNext(A_Index - 1, "Checked") == A_Index) ? 1 : 0
        lv.Modify(A_Index, "Col2", isAdmin ? "✔️ はい" : "")
        
        delayText := lv.GetText(A_Index, 3)
        delaySec := Integer(RegExReplace(delayText, "\D"))
        filePath := lv.GetText(A_Index, 4)
        
        appList.Push({path: filePath, delay: delaySec, admin: isAdmin})
    }
    
    if FileExist(iniPath) {
        try FileDelete(iniPath)
    }
        
    for index, app in appList {
        IniWrite(app.path, iniPath, "App_" index, "Path")
        IniWrite(app.delay, iniPath, "App_" index, "Delay")
        IniWrite(app.admin, iniPath, "App_" index, "Admin")
    }
    IniWrite(appList.Length, iniPath, "Settings", "Count")
    SaveErrorSetting()
}

; エラー処理の設定だけを保存する
SaveErrorSetting(*) {
    errMode := radStop.Value ? "stop" : "skip"
    IniWrite(errMode, iniPath, "Settings", "ErrorMode")
}

; 設定の読み込み
LoadSettings() {
    if !FileExist(iniPath)
        return
        
    try {
        errMode := IniRead(iniPath, "Settings", "ErrorMode", "stop")
        if (errMode == "skip") {
            radSkip.Value := 1
        } else {
            radStop.Value := 1
        }

        count := Integer(IniRead(iniPath, "Settings", "Count", "0"))
        Loop count {
            path := IniRead(iniPath, "App_" A_Index, "Path")
            delay := Integer(IniRead(iniPath, "App_" A_Index, "Delay", "0"))
            admin := Integer(IniRead(iniPath, "App_" A_Index, "Admin", "0"))
            
            if (path != "") {
                lv.Add(, A_Index, admin ? "✔️ はい" : "", delay " 秒", path)
                if (admin) {
                    lv.Modify(A_Index, "Check")
                }
                appList.Push({path: path, delay: delay, admin: admin})
            }
        }
    }
}

; 追加ボタンを押した際に種類を選ぶポップアップメニューを表示
AddTargetMenu(*) {
    m := Menu()
    m.Add("📄 ファイルを追加...", (*) => AddApp(1))
    m.Add("📁 フォルダを追加...", (*) => AddApp(2))
    m.Add("🌐 URLを追加...", (*) => AddApp(3))
    m.Show()
}

; アプリ（各種ターゲット）の追加
AddApp(type) {
    selectedTarget := ""
    if (type == 1) {
        selectedTarget := FileSelect(3, , "起動するソフトウェアを選択してください", "実行ファイル (*.exe; *.lnk)")
    } else if (type == 2) {
        selectedTarget := DirSelect(, , "開きたいフォルダを選択してください")
    } else if (type == 3) {
        ibUrl := InputBox("登録するURLを入力してください`n(例: https://google.com)", "URL設定", "w400 h150")
        if (ibUrl.Result == "Cancel" || ibUrl.Value == "")
            return
        selectedTarget := ibUrl.Value
    }
    
    if (selectedTarget == "")
        return
        
    ib := InputBox("起動するまでの「待機秒数」を入力してください（半角数字）", "秒数設定", "w300 h130", "0")
    if (ib.Result == "Cancel")
        return
        
    delaySec := IsNumber(ib.Value) ? Integer(ib.Value) : 0
    
    nextRow := lv.GetCount() + 1
    lv.Add(, nextRow, "", delaySec " 秒", selectedTarget)
    UpdateAndSave()
}

; 待機秒数の編集
EditDelay(*) {
    row := lv.GetNext()
    if (row == 0) {
        MsgBox("変更したいアイテムをリストから選択してください。", "通知", "Icon!")
        return
    }
    
    currentText := lv.GetText(row, 3)
    currentSec := RegExReplace(currentText, "\D")
    
    ib := InputBox("新しい「待機秒数」を入力してください（半角数字）", "秒数の変更", "w300 h130", currentSec)
    if (ib.Result == "Cancel")
        return
        
    newDelaySec := IsNumber(ib.Value) ? Integer(ib.Value) : 0
    
    lv.Modify(row, "Col3", newDelaySec " 秒")
    UpdateAndSave()
}

; アプリの削除
DeleteApp(*) {
    row := lv.GetNext()
    if (row == 0) {
        MsgBox("削除するアイテムを選択してください。", "通知", "Icon!")
        return
    }
    lv.Delete(row)
    UpdateAndSave()
}

; 順番を上へ移動
MoveUp(*) {
    row := lv.GetNext()
    if (row <= 1)
        return
    
    t1_chk  := (lv.GetNext(row - 1, "Checked") == row) ? 1 : 0
    t1_sec  := lv.GetText(row, 3),   t1_path := lv.GetText(row, 4)
    t2_chk  := (lv.GetNext(row - 2, "Checked") == (row - 1)) ? 1 : 0
    t2_sec  := lv.GetText(row - 1, 3), t2_path := lv.GetText(row - 1, 4)
    
    lv.Modify(row,   , row,   (t2_chk ? "✔️ はい" : ""), t2_sec, t2_path)
    lv.Modify(row-1, , row-1, (t1_chk ? "✔️ はい" : ""), t1_sec, t1_path)
    lv.Modify(row, t2_chk ? "Check" : "-Check")
    lv.Modify(row-1, t1_chk ? "Check" : "-Check")
    
    lv.Modify(row-1, "Select Focus")
    UpdateAndSave()
}

; 順番を下へ移動
MoveDown(*) {
    row := lv.GetNext()
    if (row == 0 || row == lv.GetCount())
        return
    
    t1_chk  := (lv.GetNext(row - 1, "Checked") == row) ? 1 : 0
    t1_sec  := lv.GetText(row, 3),   t1_path := lv.GetText(row, 4)
    t2_chk  := (lv.GetNext(row, "Checked") == (row + 1)) ? 1 : 0
    t2_sec  := lv.GetText(row + 1, 3), t2_path := lv.GetText(row + 1, 4)
    
    lv.Modify(row,   , row,   (t2_chk ? "✔️ はい" : ""), t2_sec, t2_path)
    lv.Modify(row+1, , row+1, (t1_chk ? "✔️ はい" : ""), t1_sec, t1_path)
    lv.Modify(row, t2_chk ? "Check" : "-Check")
    lv.Modify(row+1, t1_chk ? "Check" : "-Check")
    
    lv.Modify(row+1, "Select Focus")
    UpdateAndSave()
}

; ターゲットを安全に起動するヘルパー関数
SmartRun(targetPath, useAdmin := false) {
    isUrl := RegExMatch(targetPath, "^(?i)https?://")
    isDir := InStr(FileExist(targetPath), "D")
    
    if (isUrl || isDir || !useAdmin) {
        Run(targetPath)
    } else {
        Run("*RunAs " targetPath)
    }
}

; 選択行を今すぐ単発実行するテスト機能
TestCurrentApp(*) {
    row := lv.GetNext()
    if (row == 0) {
        MsgBox("テスト実行したいアイテムをリストから選択してください。", "通知", "Icon!")
        return
    }
    
    isAdmin := (lv.GetNext(row - 1, "Checked") == row) ? 1 : 0
    targetPath := lv.GetText(row, 4)
    
    try {
        SmartRun(targetPath, isAdmin)
    } catch {
        MsgBox("テスト起動に失敗しました:`n" . targetPath, "起動エラー", "IconX")
    }
}

; 連続実行の 開始 / 中断 を切り替える
ToggleRunApps(*) {
    global isRunning, currentRunIndex, currentRemainSec
    
    if (isRunning) {
        SetTimer(RunNextTick, 0) ; タイマー停止
        isRunning := false
        btnRun.Text := "▶️ 連続実行"
        txtStatus.Text := "❌ 中断されました"
        
        btnAdd.Enabled := true, btnEdit.Enabled := true, btnDel.Enabled := true
        btnUp.Enabled := true, btnDown.Enabled := true, btnTest.Enabled := true
        
        if (isAutoRun)
            ExitApp()
        return
    }
    
    if (appList.Length == 0) {
        if (!isAutoRun)
            MsgBox("実行するアイテムが登録されていません。", "エラー", "Icon!")
        return
    }
    
    isRunning := true
    btnRun.Text := "🛑 中断"
    
    btnAdd.Enabled := false, btnEdit.Enabled := false, btnDel.Enabled := false
    btnUp.Enabled := false, btnDown.Enabled := false, btnTest.Enabled := false
    
    currentRunIndex := 1
    PrepareNextApp()
}

; 次のアプリの待機時間をセットする
PrepareNextApp() {
    global currentRunIndex, currentRemainSec, isRunning
    
    if (currentRunIndex > appList.Length) {
        isRunning := false
        btnRun.Text := "▶️ 連続実行"
        txtStatus.Text := ""
        
        btnAdd.Enabled := true, btnEdit.Enabled := true, btnDel.Enabled := true
        btnUp.Enabled := true, btnDown.Enabled := true, btnTest.Enabled := true
        
        if (isAutoRun) {
            ExitApp()
        } else {
            MsgBox("すべての自動起動処理が終わりました。", "完了", "Iconi")
        }
        return
    }
    
    lv.Modify(currentRunIndex, "Select Focus")
    app := appList[currentRunIndex]
    currentRemainSec := app.delay
    
    SetTimer(RunNextTick, 1000)
    RunNextTick()
}

; 1秒ごとに呼ばれるタイマールーチン
RunNextTick() {
    global currentRemainSec, currentRunIndex, isRunning
    
    if (!isRunning)
        return
        
    if (currentRemainSec > 0) {
        txtStatus.Text := "⏳ あと " currentRemainSec " 秒"
        currentRemainSec--
    } else {
        SetTimer(RunNextTick, 0)
        txtStatus.Text := "🚀 起動中..."
        
        app := appList[currentRunIndex]
        
        try {
            SmartRun(app.path, app.admin)
        } catch {
            txtStatus.Text := ""
            if (radStop.Value) {
                if (!isAutoRun) {
                    MsgBox("起動に失敗したため、処理を中断しました:`n" . app.path, "エラーで停止", "IconX")
                }
                ToggleRunApps()
                return
            }
            if (!isAutoRun) {
                MsgBox("起動に失敗しました（スキップします）:`n" . app.path, "起動エラー", "IconX T3")
            } else {
                Sleep(1000)
            }
        }
        
        currentRunIndex++
        PrepareNextApp()
    }
}
