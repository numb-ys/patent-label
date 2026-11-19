;;; PatentLabel 0.2.4-2019 - one callout per command, repeated by CAD's native Space/Enter.
;;; AutoCAD 2019: CP936/GBK source, no UTF-8 BOM or LISPSYS dependency.
;;; Optional .NET UI supplies native drag preview; editing uses the command-line backend.
;;; No changes to OSNAP/UCS/security settings or global double-click bindings.

(defun bh:ui-available-p ()
  (and (member "BH:UI-READY" (atoms-family 1 '("BH:UI-READY")))
       (equal (bh:ui-ready) "0.2.4-2019")))

(defun bh:clear-preview ()
  (if (member "BH:UI-PREVIEW-CLEAR" (atoms-family 1 '("BH:UI-PREVIEW-CLEAR")))
    (vl-catch-all-apply 'bh:ui-preview-clear nil))
  (redraw))

;;; Accept a plain coordinate list and the one-item wrapper returned by older DLLs.
(defun bh:point-result (value)
  (if (and (listp value) (= (length value) 1) (listp (car value)))
    (setq value (car value)))
  (if value
    (progn
      (bh:require (and (listp value) (member (length value) '(2 3))
                       (vl-every 'numberp value))
                  "插件返回的坐标格式不正确，请重启 CAD 加载新版。")
      (if (= (length value) 2) (append value '(0.0)) value))
    nil))

(defun bh:sync-ui ()
  (if (bh:ui-available-p)
    (bh:ui-configure (if (bh:enter-only-p) "Enter" "Space")
                    (if (bh:bold-p) "Bold" "Regular"))))

(defun bh:bold-p ()
  (equal (getenv "PatentLabel.SimHeiWeight") "Bold"))

(defun bh:text-style ()
  (if bh:label-style bh:label-style
    (if (bh:bold-p) "PATENT_LABEL_SIMHEI_BOLD" "PATENT_LABEL_SIMHEI_REGULAR")))

(defun bh:ensure-font-style (name file)
  (if (not (tblsearch "STYLE" name))
    (bh:require
      (bh:record-write
        (entmake (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord")
                       '(100 . "AcDbTextStyleTableRecord") (cons 2 name)
                       '(70 . 0) '(40 . 0.0) '(41 . 1.0) '(50 . 0.0) '(71 . 0)
                       '(42 . 2.5) (cons 3 file) '(4 . ""))))
      "无法创建标号字体样式。")))

(defun bh:setting-real (key fallback / value)
  (setq value (getenv (strcat "PatentLabel." key)))
  (if (and value (setq value (distof value 2)) (> value 0.0))
    value fallback))

(defun bh:settings ()
  (list (bh:setting-real "Height" 2.5)
        (bh:setting-real "Landing" 3.75)
        (bh:setting-real "Gap" 0.8)))

(defun bh:enter-only-p ()
  (equal (getenv "PatentLabel.Confirm") "Enter"))

(defun bh:digits-p (value / code valid)
  (setq valid (and (eq (type value) 'STR) (> (strlen value) 0)
                   (<= (strlen value) 32)))
  (if valid
    (foreach code (vl-string->list value)
      (if (or (< code 48) (> code 57)) (setq valid nil))))
  valid)

(defun bh:identifier-p (value / code valid)
  (setq valid (and (eq (type value) 'STR) (> (strlen value) 0)
                   (<= (strlen value) 32)))
  (if valid
    (foreach code (vl-string->list value)
      (if (not (or (and (>= code 48) (<= code 57))
                   (and (>= code 65) (<= code 90))
                   (and (>= code 97) (<= code 122))))
        (setq valid nil))))
  valid)

;;; Decimal string arithmetic avoids AutoLISP integer overflow and keeps 001 -> 002.
(defun bh:increment-digits (value / index digit carry result)
  (setq index (strlen value) carry T result "")
  (while (> index 0)
    (setq digit (ascii (substr value index 1)))
    (if carry
      (if (= digit 57) (setq digit 48) (setq digit (1+ digit) carry nil)))
    (setq result (strcat (chr digit) result) index (1- index)))
  (if carry (strcat "1" result) result))

(defun bh:increment-letters (value / index code carry result)
  (setq index (strlen value) carry T result "")
  (while (> index 0)
    (setq code (ascii (substr value index 1)))
    (if carry
      (cond ((= code 90) (setq code 65))
            ((= code 122) (setq code 97))
            (T (setq code (1+ code) carry nil))))
    (setq result (strcat (chr code) result) index (1- index)))
  (if carry (strcat (if (<= (ascii (substr value 1 1)) 90) "A" "a") result) result))

(defun bh:increment (value / index digits-tail code prefix suffix)
  (setq index (strlen value)
        digits-tail (bh:digits-p (substr value index 1)))
  (while (and (> index 0)
              (equal (bh:digits-p (substr value index 1)) digits-tail))
    (setq index (1- index)))
  (setq prefix (if (> index 0) (substr value 1 index) "")
        suffix (substr value (1+ index)))
  (strcat prefix (if digits-tail (bh:increment-digits suffix) (bh:increment-letters suffix))))

(defun bh:read-number (suggestion / value done hint)
  (setq hint (if (bh:enter-only-p) "Enter 确认" "空格或 Enter 确认"))
  (while (not done)
    (setq value
      (getstring (bh:enter-only-p)
        (strcat "\n输入编号（数字/英文字母，最多32个字符，" hint "，Esc 退出）"
                (if suggestion (strcat " <" suggestion ">") "") ": ")))
    (if (and (or (null value) (equal value "")) suggestion) (setq value suggestion))
    (if (bh:identifier-p value)
      (setq done T)
      (prompt "\n请输入数字或英文字母，例如 123、A、A01；最多32个字符，不接受空编号或空格。")))
  value)

(defun bh:require (value message)
  (if (not value) (progn (prompt (strcat "\n" message)) (exit)))
  value)

(defun bh:record-write (value)
  (if (and value undo-open) (setq undo-dirty T))
  value)

(defun bh:check-layer (name / layer)
  (setq layer (tblsearch "LAYER" name))
  (bh:require
    (and layer (= 0 (logand 5 (cdr (assoc 70 layer))))
         (> (cdr (assoc 62 layer)) 0))
    (strcat name " 图层已关闭、冻结或锁定，请先启用并解锁。")))

(defun bh:ensure-resources (/ layer style)
  (if (not (tblsearch "LAYER" "PATENT_LABEL"))
    (bh:require
      (bh:record-write (entmake '((0 . "LAYER") (100 . "AcDbSymbolTableRecord")
                 (100 . "AcDbLayerTableRecord") (2 . "PATENT_LABEL")
                 (70 . 0) (62 . 7) (6 . "Continuous") (370 . 18))))
      "无法创建标号图层。"))
  (bh:check-layer "PATENT_LABEL")
  (if (not (tblsearch "STYLE" "PATENT_LABEL_NUM"))
    (bh:require
      (bh:record-write (entmake '((0 . "STYLE") (100 . "AcDbSymbolTableRecord")
                 (100 . "AcDbTextStyleTableRecord") (2 . "PATENT_LABEL_NUM")
                 (70 . 0) (40 . 0.0) (41 . 1.0) (50 . 0.0) (71 . 0)
                 (42 . 2.5) (3 . "txt.shx") (4 . ""))))
      "无法创建数字文字样式。"))
  (if (bh:ui-available-p)
    (bh:record-write (bh:ui-ensure-fonts))
    (progn (bh:ensure-font-style "PATENT_LABEL_SIMHEI_BOLD" "simhei.ttf")
           (bh:ensure-font-style "PATENT_LABEL_SIMHEI_REGULAR" "simhei.ttf")))
  T)

(defun bh:text-width (number height / box)
  (setq box (textbox (list '(0 . "TEXT") (cons 1 number)
                          (cons 40 height) '(41 . 1.0) '(50 . 0.0)
                          (cons 7 (bh:text-style)))))
  (bh:require box "无法计算数字宽度，请检查文字字体。")
  (max (* height 0.15) (- (car (cadr box)) (caar box))))

;;; Geometry is local to the number's center. The tail points toward the target.
;;; A near-vertical leader uses a stable side bend instead of reversing its tail.
(defun bh:geometry (tip number height landing gap / half side end elbow reach)
  (setq half (/ (bh:text-width number height) 2.0)
        side (if (< (car tip) 0.0) -1.0 1.0)
        end (list (* side (+ half gap)) 0.0 0.0)
        reach (- (abs (car tip)) (+ half gap)))
  (if (and (<= (abs (car tip)) (+ half gap))
           (<= (abs (cadr tip)) (+ (/ height 2.0) gap)))
    nil
    (progn
      (setq elbow
        (list (+ (car end)
                 (* side (if (> reach 0.0) (min landing reach) landing)))
              0.0 0.0))
      (list tip elbow end))))

(defun bh:attribute-data (kind number point height rotation normal / data)
  (setq data
    (list (cons 0 kind) '(8 . "0") '(62 . 0) '(370 . -2) (cons 10 point)
          (cons 11 point) (cons 40 height) (cons 1 number)
          '(2 . "NUMBER") '(70 . 0) '(72 . 1) '(74 . 2)
          '(41 . 1.0) '(51 . 0.0) '(71 . 0)
          (cons 50 rotation) (cons 7 (bh:text-style)) (cons 210 normal)))
  (if (= kind "ATTDEF") (append data '((3 . "编号"))) data))

(defun bh:make-definition (tip number height landing gap / points block)
  (setq points (bh:geometry tip number height landing gap))
  (bh:require points "编号位置离指向点太近，数字会遮挡指向点，请重新选择位置。")
  (bh:require
    (entmake '((0 . "BLOCK") (2 . "*U") (70 . 1) (10 0.0 0.0 0.0)))
    "无法创建标号块。")
  (bh:require
    (entmake
      (append '((0 . "LWPOLYLINE") (100 . "AcDbEntity") (8 . "0")
                (62 . 0) (370 . -2) (100 . "AcDbPolyline") (90 . 3) (70 . 0))
              (mapcar '(lambda (p) (cons 10 (list (car p) (cadr p)))) points)))
    "无法创建标号折线。")
  (bh:require
    (entmake (bh:attribute-data "ATTDEF" number '(0.0 0.0 0.0)
                               height 0.0 '(0.0 0.0 1.0)))
    "无法创建编号属性定义。")
  (setq block (bh:record-write (entmake '((0 . "ENDBLK")))))
  (bh:require block "无法结束标号块定义。")
  block)

(defun bh:metadata (tip height landing gap)
  (list -3 (list "PATENT_LABEL" '(1000 . "1") (cons 1010 tip)
                 (cons 1040 height) (cons 1040 landing) (cons 1040 gap))))

(defun bh:make-label (target center number settings / height landing gap tip
                     normal axis rotation insertion block entity bh:label-style)
  (setq bh:label-style (bh:text-style))
  (setq height (nth 0 settings) landing (nth 1 settings) gap (nth 2 settings)
        center (list (car center) (cadr center) (caddr target))
        tip (list (- (car target) (car center))
                  (- (cadr target) (cadr center)) 0.0))
  (bh:require (bh:identifier-p number) "编号只能包含数字或英文字母，最多32个字符。")
  (bh:ensure-resources)
  (setq block (bh:make-definition tip number height landing gap)
        normal (trans '(0.0 0.0 1.0) 1 0 T)
        axis (trans (trans '(1.0 0.0 0.0) 1 0 T) 0 normal T)
        rotation (atan (cadr axis) (car axis))
        insertion (trans (trans center 1 0) 0 normal))
  (if (not (tblsearch "APPID" "PATENT_LABEL"))
    (bh:record-write (regapp "PATENT_LABEL")))
  (bh:require
    (entmake
      (list '(0 . "INSERT") '(8 . "PATENT_LABEL") '(62 . 256)
            (cons 2 block) '(66 . 1) (cons 10 insertion)
            '(41 . 1.0) '(42 . 1.0) '(43 . 1.0) (cons 50 rotation)
            (cons 210 normal) (bh:metadata tip height landing gap)))
    "无法插入标号块。")
  (bh:require
    (entmake (bh:attribute-data "ATTRIB" number insertion height rotation normal))
    "无法创建编号文字。")
  (bh:require (entmake '((0 . "SEQEND"))) "无法结束编号属性。")
  (setq entity (entlast))
  (entupd entity)
  entity)

(defun bh:label-p (entity / data)
  (and entity (setq data (entget entity '("PATENT_LABEL")))
       (= (cdr (assoc 0 data)) "INSERT")
       (assoc -3 data)))

(defun bh:attribute (entity / child found)
  (setq child (entnext entity))
  (while (and child (not found)
              (/= (cdr (assoc 0 (entget child))) "SEQEND"))
    (if (and (= (cdr (assoc 0 (entget child))) "ATTRIB")
             (= (cdr (assoc 2 (entget child))) "NUMBER"))
      (setq found child)
      (setq child (entnext child))))
  found)

;;; Clone-on-edit: copied block references may share a definition.
(defun bh:replace-number (entity number)
  (bh:replace-label entity number nil))

(defun bh:replace-label (entity number requested-style / data meta block attribute attrdata bh:label-style)
  (bh:require (bh:label-p entity) "所选对象不是本插件创建的标号。")
  (bh:require (bh:identifier-p number) "编号只能包含数字或英文字母，最多32个字符。")
  (setq data (entget entity '("PATENT_LABEL"))
        meta (cdr (cadr (assoc -3 data)))
        attribute (bh:attribute entity))
  (bh:require attribute "标号的编号属性丢失。")
  (setq bh:label-style (if requested-style requested-style (cdr (assoc 7 (entget attribute)))))
  (bh:require (= (cdr (nth 0 meta)) "1") "标号数据版本不支持。")
  (bh:check-layer (cdr (assoc 8 data)))
  (bh:ensure-resources)
  (setq block (bh:make-definition (cdr (nth 1 meta)) number
                                (cdr (nth 2 meta)) (cdr (nth 3 meta))
                                (cdr (nth 4 meta))))
  (bh:require (entmod (subst (cons 2 block) (assoc 2 data) data))
              "无法更新标号折线。")
  (setq attrdata (entget attribute))
  (setq attrdata (subst (cons 7 bh:label-style) (assoc 7 attrdata) attrdata))
  (bh:require (entmod (subst (cons 1 number) (assoc 1 attrdata) attrdata))
              "无法更新编号文字。")
  (entupd entity)
  entity)

;;; A transaction is opened only after all interactive input is complete.
;;; Its caller binds undo-open locally so the error handler can roll back safely.
(defun bh:begin-undo ()
  ; AutoCAD's automatic command group can already set bit 8 here.
  ; Explicit Begin is required to split repeated labels into separate groups.
  (bh:require (= 1 (logand 3 (getvar "UNDOCTL")))
              "请先将 UNDO 控制设置为 All（全部），再使用标号。")
  (command-s "_.UNDO" "_Begin")
  (setq undo-open T undo-dirty nil))

(defun bh:end-undo ()
  (command-s "_.UNDO" "_End")
  (setq undo-open nil undo-dirty nil)
  (bh:clear-preview))

(defun bh:rollback ()
  (bh:clear-preview)
  (entmake)
  (command-s "_.UNDO" "_End")
  (if undo-dirty (command-s "_.U"))
  (setq undo-open nil undo-dirty nil))

(defun bh:on-error (message)
  (bh:clear-preview)
  (if undo-open (bh:rollback))
  (redraw)
  (if (not (wcmatch (strcase message) "*CANCEL*,*QUIT*,*BREAK*,*取消*,*退出*"))
    (prompt (strcat "\n标号未完成：" message)))
  (princ))

(defun c:BH (/ *error* undo-open undo-dirty target center number settings points running suggestion)
  (setq *error* bh:on-error running T settings (bh:settings)
        suggestion (if (bh:identifier-p bh:next) bh:next "1"))
  (prompt "\n单次标号：指向点 -> 编号位置 -> 输入编号 -> 确认结束；再次按空格由 CAD 重复 BH。")
  (while running
    (initget "Settings")
    (setq target (getpoint "\n点取引线指向点 [设置(Settings)] <结束>: "))
    (cond
      ((null target) (setq running nil))
      ((equal target "Settings") (c:BHSZ) (setq settings (bh:settings)))
      (T
        (if (bh:ui-available-p)
          (progn
            (bh:begin-undo)
            (bh:ensure-resources)
            (setq center (bh:point-result
              (bh:ui-place target suggestion
                           (nth 0 settings) (nth 1 settings) (nth 2 settings)))))
          (setq center (getpoint target "\n点取数字中心位置 <取消本条>: ")))
        (if center
          (progn
            (setq number (bh:read-number suggestion))
            (if (not undo-open) (bh:begin-undo))
            (bh:ensure-resources)
            (setq points (bh:geometry
                    (list (- (car target) (car center))
                          (- (cadr target) (cadr center)) 0.0)
                    number (nth 0 settings) (nth 1 settings) (nth 2 settings)))
            (if points
              (progn
                (bh:make-label target center number settings)
                (bh:end-undo)
                (setq bh:next (bh:increment number))
                (if (> (strlen bh:next) 32) (setq bh:next nil))
                (setq running nil))
              (progn
                (bh:rollback)
                (prompt "\n数字位置离指向点太近，本条未生成，请重新点取。"))))
          (progn (if undo-open (bh:rollback)) (setq running nil))))))
  (princ))

(defun c:BHSZ (/ values height landing gap confirm weight)
  (setq values (bh:settings))
  (initget 6)
  (setq height (getreal (strcat "\n数字高度 <" (rtos (nth 0 values) 2 3) ">: ")))
  (initget 6)
  (setq landing (getreal (strcat "\n折线水平段长度 <" (rtos (nth 1 values) 2 3) ">: ")))
  (initget 6)
  (setq gap (getreal (strcat "\n引线与数字间隙 <" (rtos (nth 2 values) 2 3) ">: ")))
  (initget "Space Enter")
  (setq confirm
    (getkword (strcat "\n编号确认键 [空格或回车(Space)/仅回车(Enter)] <"
                     (if (bh:enter-only-p) "Enter" "Space") ">: ")))
  (initget "Bold Regular")
  (setq weight (getkword
    (strcat "\n新建编号字重 [加粗(Bold)/不加粗(Regular)] <"
            (if (bh:bold-p) "Bold" "Regular") ">: ")))
  (if height (setenv "PatentLabel.Height" (rtos height 2 8)))
  (if landing (setenv "PatentLabel.Landing" (rtos landing 2 8)))
  (if gap (setenv "PatentLabel.Gap" (rtos gap 2 8)))
  (if confirm (setenv "PatentLabel.Confirm" confirm))
  (if weight (setenv "PatentLabel.SimHeiWeight" weight))
  (bh:sync-ui)
  (prompt "\n设置已保存，对之后新建的标号生效。")
  (princ))

(defun bh:set-weight (entity weight / attribute)
  (bh:require (bh:label-p entity) "请选择本工具创建的标号。")
  (setq attribute (bh:attribute entity))
  (bh:require attribute "标号的编号属性丢失。")
  (bh:replace-label entity (cdr (assoc 1 (entget attribute)))
                    (if (equal weight "Regular") "PATENT_LABEL_SIMHEI_REGULAR" "PATENT_LABEL_SIMHEI_BOLD")))

(defun c:BHJC (/ *error* undo-open undo-dirty selected weight index)
  (setq *error* bh:on-error)
  (prompt "\n选择要改为黑体并调整字重的已有标号: ")
  (setq selected (ssget '((0 . "INSERT") (-3 ("PATENT_LABEL")))))
  (if selected
    (progn
      (initget "Bold Regular")
      (setq weight (getkword (strcat "\n所选编号字重 [加粗(Bold)/不加粗(Regular)] <"
                                   (if (bh:bold-p) "Bold" "Regular") ">: ")))
      (if (null weight) (setq weight (if (bh:bold-p) "Bold" "Regular")))
      (bh:begin-undo)
      (setq index 0)
      (repeat (sslength selected)
        (bh:set-weight (ssname selected index) weight)
        (setq index (1+ index)))
      (bh:end-undo)
      (prompt "\n所选编号已改为黑体并更新字重，引线粗细保持不变。")))
  (princ))

(defun c:BHXG (/ *error* undo-open undo-dirty selection entity attribute number)
  (setq *error* bh:on-error)
  (setq selection (entsel "\n选择要修改编号的标号（引线或数字）: "))
  (if selection
    (progn
      (setq entity (car selection))
      (if (= (cdr (assoc 0 (entget entity))) "ATTRIB")
        (setq entity (cdr (assoc 330 (entget entity)))))
      (bh:require (bh:label-p entity) "请选择由 BH 创建的完整标号块。")
      (setq attribute (bh:attribute entity))
      (bh:require attribute "标号的编号属性丢失。")
      (setq number (bh:read-number (cdr (assoc 1 (entget attribute)))))
      (bh:begin-undo)
      (bh:replace-number entity number)
      (bh:end-undo)))
  (princ))

(defun bh:ui-apply (handle number / *error* undo-open undo-dirty entity)
  (setq *error* bh:on-error entity (handent handle))
  (bh:require (bh:label-p entity) "标号已删除或不在当前图纸中。")
  (bh:begin-undo)
  (bh:replace-number entity number)
  (bh:end-undo)
  (princ))

(defun c:BHHELP ()
  (prompt "\nBH：单次标号；BHSZ：字高/折线/间隙/确认键/字重；BHXG：改号；BHJC：修改已有标号字重。")
  (prompt "\n确认编号即结束命令；再次空格/回车由 CAD 重复 BH，仍保留下一编号建议。U 在 CAD 命令行撤销。")
  (prompt "\n数字点击位置为中心；默认无箭头，左右自动折线；使用当前 UCS 平面和当前空间。")
  (princ))

(defun c:BHVER ()
  (prompt (strcat "\nPatentLabel 0.2.4-2019 | CAD " (getvar "ACADVER")))
  (prompt (if (bh:ui-available-p) "\n2019 预览模块：已加载。" "\n2019 预览模块：未加载，当前为基础模式。"))
  (prompt (strcat "\n黑体文件：" (if (findfile "simhei.ttf") (findfile "simhei.ttf") "未找到")))
  (princ))

(bh:sync-ui)
(prompt "\n专利附图标号 0.2.4-2019 已加载。输入 BH 开始，BHSZ 设置，BHHELP 查看帮助。")
(if (bh:ui-available-p)
  (prompt "\n整条折线随鼠标预览已启用；BHXG 在命令行修改编号。")
  (prompt "\n当前为基础模式；NETLOAD 加载配套 PatentLabel.UI2019.dll 可启用整条折线预览。"))
(princ)
