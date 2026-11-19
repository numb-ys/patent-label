;;; PatentLabel 0.3.2 - one callout per command, repeated by CAD's native Space/Enter.
;;; ASCII English source, compatible with legacy and Unicode AutoLISP engines.
;;; Optional .NET UI supplies native drag preview; editing uses the command-line backend.
;;; No changes to OSNAP/UCS/security settings or global double-click bindings.

(defun bh:ui-available-p ()
  (and (member "BH:UI-READY" (atoms-family 1 '("BH:UI-READY")))
       (equal (bh:ui-ready) "0.3.2")))

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
                  "The plug-in returned an invalid point. Restart AutoCAD to load the matching version.")
      (if (= (length value) 2) (append value '(0.0)) value))
    nil))

(defun bh:sync-ui ()
  (if (bh:ui-available-p)
    (bh:ui-configure (if (bh:enter-only-p) "Enter" "Space")
                    (if (bh:bold-p) "Bold" "Regular"))))

(defun bh:bold-p ()
  (equal (getenv "PatentLabel.EnglishWeight") "Bold"))

(defun bh:text-style ()
  (if bh:label-style bh:label-style
    (if (bh:bold-p) "PATENT_LABEL_ARIAL_BOLD" "PATENT_LABEL_ARIAL_REGULAR")))

(defun bh:ensure-font-style (name file)
  (if (not (tblsearch "STYLE" name))
    (bh:require
      (bh:record-write
        (entmake (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord")
                       '(100 . "AcDbTextStyleTableRecord") (cons 2 name)
                       '(70 . 0) '(40 . 0.0) '(41 . 1.0) '(50 . 0.0) '(71 . 0)
                       '(42 . 2.5) (cons 3 file) '(4 . ""))))
      "Could not create the callout text style.")))

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
  (setq hint (if (bh:enter-only-p) "Enter to confirm" "Space or Enter to confirm"))
  (while (not done)
    (setq value
      (getstring (bh:enter-only-p)
        (strcat "\nEnter label (letters/digits, up to 32 characters, " hint ", Esc to cancel)"
                (if suggestion (strcat " <" suggestion ">") "") ": ")))
    (if (and (or (null value) (equal value "")) suggestion) (setq value suggestion))
    (if (bh:identifier-p value)
      (setq done T)
      (prompt "\nUse 1-32 letters or digits, for example 123, A or A01. Empty labels and spaces are not allowed.")))
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
    (strcat name " layer is off, frozen or locked. Turn it on, thaw and unlock it first.")))

(defun bh:ensure-resources (/ layer style)
  (if (not (tblsearch "LAYER" "PATENT_LABEL"))
    (bh:require
      (bh:record-write (entmake '((0 . "LAYER") (100 . "AcDbSymbolTableRecord")
                 (100 . "AcDbLayerTableRecord") (2 . "PATENT_LABEL")
                 (70 . 0) (62 . 7) (6 . "Continuous") (370 . 18))))
      "Could not create the callout layer."))
  (bh:check-layer "PATENT_LABEL")
  (if (not (tblsearch "STYLE" "PATENT_LABEL_NUM"))
    (bh:require
      (bh:record-write (entmake '((0 . "STYLE") (100 . "AcDbSymbolTableRecord")
                 (100 . "AcDbTextStyleTableRecord") (2 . "PATENT_LABEL_NUM")
                 (70 . 0) (40 . 0.0) (41 . 1.0) (50 . 0.0) (71 . 0)
                 (42 . 2.5) (3 . "txt.shx") (4 . ""))))
      "Could not create the legacy text style."))
  (if (bh:ui-available-p)
    (bh:record-write (bh:ui-ensure-fonts))
    (progn (bh:ensure-font-style "PATENT_LABEL_ARIAL_BOLD" "arialbd.ttf")
           (bh:ensure-font-style "PATENT_LABEL_ARIAL_REGULAR" "arial.ttf")))
  T)

(defun bh:text-width (number height / box)
  (setq box (textbox (list '(0 . "TEXT") (cons 1 number)
                          (cons 40 height) (cons 41 (if bh:label-width bh:label-width 1.0)) '(50 . 0.0)
                          (cons 7 (bh:text-style)))))
  (bh:require box "Could not measure the label. Check the text font.")
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
  (if (= kind "ATTDEF") (append data '((3 . "Label"))) data))

(defun bh:make-definition (tip number height landing gap / points block offset)
  (setq offset (if bh:label-offset bh:label-offset '(0.0 0.0 0.0)))
  (setq points (bh:geometry (mapcar '- tip offset) number height landing gap))
  (bh:require points "The label is too close to the target point. Choose another label position.")
  (setq points (mapcar '(lambda (point) (mapcar '+ point offset)) points))
  (bh:require
    (entmake '((0 . "BLOCK") (2 . "*U") (70 . 1) (10 0.0 0.0 0.0)))
    "Could not create the callout block.")
  (bh:require
    (entmake
      (append '((0 . "LWPOLYLINE") (100 . "AcDbEntity") (8 . "0")
                (62 . 0) (370 . -2) (100 . "AcDbPolyline") (90 . 3) (70 . 0))
              (mapcar '(lambda (p) (cons 10 (list (car p) (cadr p)))) points)))
    "Could not create the callout leader.")
  (bh:require
    (entmake (bh:attribute-data "ATTDEF" number offset
                               height 0.0 '(0.0 0.0 1.0)))
    "Could not create the label attribute definition.")
  (setq block (bh:record-write (entmake '((0 . "ENDBLK")))))
  (bh:require block "Could not finish the callout block definition.")
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
  (bh:require (bh:identifier-p number) "Use 1-32 ASCII letters or digits for the label.")
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
    "Could not insert the callout block.")
  (bh:require
    (entmake (bh:attribute-data "ATTRIB" number insertion height rotation normal))
    "Could not create the label attribute.")
  (bh:require (entmake '((0 . "SEQEND"))) "Could not finish the label attribute sequence.")
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
(defun bh:attribute-center (attribute / data)
  (setq data (entget attribute))
  (trans (cdr (assoc (if (and (= (cdr (assoc 72 data)) 0) (= (cdr (assoc 74 data)) 0)) 10 11) data)) attribute 0))

;;; Convert WCS points to the INSERT's local frame, including rotation and scale.
(defun bh:block-local (entity point / data relative angle sx sy sz)
  (setq data (entget entity)
        relative (mapcar '- (trans point 0 (cdr (assoc 210 data))) (cdr (assoc 10 data)))
        angle (cdr (assoc 50 data)) sx (cdr (assoc 41 data))
        sy (cdr (assoc 42 data)) sz (cdr (assoc 43 data)))
  (list (/ (+ (* (car relative) (cos angle)) (* (cadr relative) (sin angle))) sx)
        (/ (- (* (cadr relative) (cos angle)) (* (car relative) (sin angle))) sy)
        (/ (caddr relative) sz)))

(defun bh:replace-number (entity number)
  (bh:replace-label entity number nil))

(defun bh:replace-label (entity number requested-style / data meta block attribute attrdata height bh:label-style bh:label-offset bh:label-width)
  (bh:require (bh:label-p entity) "The selected object is not a PatentLabel callout.")
  (bh:require (bh:identifier-p number) "Use 1-32 ASCII letters or digits for the label.")
  (setq data (entget entity '("PATENT_LABEL"))
        meta (cdr (cadr (assoc -3 data)))
        attribute (bh:attribute entity))
  (bh:require attribute "The callout NUMBER attribute is missing.")
  (setq bh:label-style (if requested-style requested-style (cdr (assoc 7 (entget attribute)))))
  (setq attrdata (entget attribute)
        bh:label-offset (bh:block-local entity (bh:attribute-center attribute))
        bh:label-width (cdr (assoc 41 attrdata))
        height (/ (cdr (assoc 40 attrdata)) (abs (cdr (assoc 42 data)))))
  (bh:require (= (cdr (nth 0 meta)) "1") "This callout data version is not supported.")
  (bh:check-layer (cdr (assoc 8 data)))
  (bh:ensure-resources)
  (setq block (bh:make-definition (cdr (nth 1 meta)) number
                                height (cdr (nth 3 meta))
                                (cdr (nth 4 meta))))
  (setq data (subst (bh:metadata (cdr (nth 1 meta)) height (cdr (nth 3 meta)) (cdr (nth 4 meta))) (assoc -3 data) data))
  (bh:require (entmod (subst (cons 2 block) (assoc 2 data) data))
              "Could not update the leader.")
  (setq attrdata (entget attribute))
  (setq attrdata (subst (cons 7 bh:label-style) (assoc 7 attrdata) attrdata))
  (bh:require (entmod (subst (cons 1 number) (assoc 1 attrdata) attrdata))
              "Could not update the label text.")
  (entupd entity)
  entity)

(defun bh:move-label (entity center / attribute data original desired normal local delta)
  (bh:require (bh:label-p entity) "Select a complete callout block created by BH.")
  (bh:check-layer (cdr (assoc 8 (entget entity))))
  (setq attribute (bh:attribute entity))
  (bh:require attribute "The callout NUMBER attribute is missing.")
  (setq data (entget attribute)
        original (bh:attribute-center attribute)
        normal (cdr (assoc 210 (entget entity)))
        desired (trans center 1 normal)
        local (cdr (assoc 10 (entget entity))))
  ;; Keep the moved text on the original callout plane.
  (setq desired (trans (list (car desired) (cadr desired) (caddr local)) normal 0)
        delta (trans (mapcar '- desired original) 0 attribute T))
  (foreach code '(10 11)
    (if (assoc code data)
      (setq data (subst (cons code (mapcar '+ (cdr (assoc code data)) delta)) (assoc code data) data))))
  (bh:require (bh:record-write (entmod data)) "Cannot move the label attribute.")
  (bh:replace-number entity (cdr (assoc 1 data))))

;;; A transaction is opened only after all interactive input is complete.
;;; Its caller binds undo-open locally so the error handler can roll back safely.
(defun bh:begin-undo ()
  ; AutoCAD's automatic command group can already set bit 8 here.
  ; Explicit Begin is required to split repeated labels into separate groups.
  (bh:require (= 1 (logand 3 (getvar "UNDOCTL")))
              "Set UNDO Control to All before creating or editing callouts.")
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
  (if (not (wcmatch (strcase message) "*CANCEL*,*QUIT*,*BREAK*"))
    (prompt (strcat "\nCallout not completed: " message)))
  (princ))

(defun c:BH (/ *error* undo-open undo-dirty target center number settings points running suggestion)
  (setq *error* bh:on-error running T settings (bh:settings)
        suggestion (if (bh:identifier-p bh:next) bh:next "1"))
  (prompt "\nOne callout: target point -> label position -> label -> confirm to finish. Press Space again to repeat BH.")
  (while running
    (initget "Settings")
    (setq target (getpoint "\nPick leader target point [Settings] <Finish>: "))
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
          (setq center (getpoint target "\nPick label center <Cancel this callout>: ")))
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
                (prompt "\nThe label is too close to the target. No callout was created; pick again."))))
          (progn (if undo-open (bh:rollback)) (setq running nil))))))
  (princ))

(defun c:BHSZ (/ values height landing gap confirm weight)
  (setq values (bh:settings))
  (initget 6)
  (setq height (getreal (strcat "\nLabel height <" (rtos (nth 0 values) 2 3) ">: ")))
  (initget 6)
  (setq landing (getreal (strcat "\nHorizontal landing length <" (rtos (nth 1 values) 2 3) ">: ")))
  (initget 6)
  (setq gap (getreal (strcat "\nLeader-to-label gap <" (rtos (nth 2 values) 2 3) ">: ")))
  (initget "Space Enter")
  (setq confirm
    (getkword (strcat "\nConfirmation key [Space/Enter] <"
                     (if (bh:enter-only-p) "Enter" "Space") ">: ")))
  (initget "Bold Regular")
  (setq weight (getkword
    (strcat "\nNew label weight [Bold/Regular] <"
            (if (bh:bold-p) "Bold" "Regular") ">: ")))
  (if height (setenv "PatentLabel.Height" (rtos height 2 8)))
  (if landing (setenv "PatentLabel.Landing" (rtos landing 2 8)))
  (if gap (setenv "PatentLabel.Gap" (rtos gap 2 8)))
  (if confirm (setenv "PatentLabel.Confirm" confirm))
  (if weight (setenv "PatentLabel.EnglishWeight" weight))
  (bh:sync-ui)
  (prompt "\nSettings saved for new callouts.")
  (princ))

(defun bh:set-weight (entity weight / attribute)
  (bh:require (bh:label-p entity) "Select a callout created by PatentLabel.")
  (setq attribute (bh:attribute entity))
  (bh:require attribute "The callout NUMBER attribute is missing.")
  (bh:replace-label entity (cdr (assoc 1 (entget attribute)))
                    (if (equal weight "Regular") "PATENT_LABEL_ARIAL_REGULAR" "PATENT_LABEL_ARIAL_BOLD")))

(defun c:BHJC (/ *error* undo-open undo-dirty selected weight index)
  (setq *error* bh:on-error)
  (prompt "\nSelect callouts to change to Arial and set their weight: ")
  (setq selected (ssget '((0 . "INSERT") (-3 ("PATENT_LABEL")))))
  (if selected
    (progn
      (initget "Bold Regular")
      (setq weight (getkword (strcat "\nSelected label weight [Bold/Regular] <"
                                   (if (bh:bold-p) "Bold" "Regular") ">: ")))
      (if (null weight) (setq weight (if (bh:bold-p) "Bold" "Regular")))
      (bh:begin-undo)
      (setq index 0)
      (repeat (sslength selected)
        (bh:set-weight (ssname selected index) weight)
        (setq index (1+ index)))
      (bh:end-undo)
      (prompt "\nSelected labels now use Arial with the chosen weight. Leader lineweight is unchanged.")))
  (princ))

(defun c:BHXG (/ *error* undo-open undo-dirty selection entity attribute number)
  (setq *error* bh:on-error)
  (setq selection (entsel "\nSelect a callout to edit (leader or label): "))
  (if selection
    (progn
      (setq entity (car selection))
      (if (= (cdr (assoc 0 (entget entity))) "ATTRIB")
        (setq entity (cdr (assoc 330 (entget entity)))))
      (bh:require (bh:label-p entity) "Select a complete callout block created by BH.")
      (setq attribute (bh:attribute entity))
      (bh:require attribute "The callout NUMBER attribute is missing.")
      (setq number (bh:read-number (cdr (assoc 1 (entget attribute)))))
      (bh:begin-undo)
      (bh:replace-number entity number)
      (bh:end-undo)))
  (princ))

(defun c:BHYD (/ *error* undo-open undo-dirty selection entity center)
  (setq *error* bh:on-error)
  (setq selection (entsel "\nSelect a callout to reposition (leader or label): "))
  (if selection
    (progn
      (setq entity (car selection))
      (if (= (cdr (assoc 0 (entget entity))) "ATTRIB")
        (setq entity (cdr (assoc 330 (entget entity)))))
      (bh:require (bh:label-p entity) "Select a complete callout block created by BH.")
      (if (bh:ui-available-p)
        (setq center (bh:point-result (bh:ui-move-label (cdr (assoc 5 (entget entity))))))
        (setq center (getpoint (trans (bh:attribute-center (bh:attribute entity)) 0 1) "\nPick the new label center <Cancel>: ")))
      (if center
        (progn (bh:begin-undo) (bh:move-label entity center) (bh:end-undo)))))
  (bh:clear-preview)
  (princ))

(defun bh:ui-apply (handle number / *error* undo-open undo-dirty entity)
  (setq *error* bh:on-error entity (handent handle))
  (bh:require (bh:label-p entity) "The callout was deleted or is not in the current drawing.")
  (bh:begin-undo)
  (bh:replace-number entity number)
  (bh:end-undo)
  (princ))

(defun c:BHHELP ()
  (prompt "\nBH: create one callout. BHSZ: height/landing/gap/confirmation/weight. BHXG: edit label. BHJC: change label font and weight.")
  (prompt "\nConfirm the label to finish. Press Space/Enter again to repeat BH with the next suggested label. Use U at the command prompt to undo.")
  (prompt "\nThe second point is the label center. No arrowhead; the leader bends left/right automatically. Uses the current UCS and space.")
  (prompt "\nSelect a callout and drag its blue label-center grip for live leader preview with a fixed target. BHYD is also available.")
  (princ))

(bh:sync-ui)
(prompt "\nPatentLabel 0.3.2 loaded (English). Type BH to start, BHSZ for settings, BHHELP for help.")
(if (bh:ui-available-p)
  (prompt "\nFull leader preview is enabled. Use BHXG to edit labels at the command line.")
  (prompt "\nBasic mode. NETLOAD the matching PatentLabel assembly to enable full leader preview."))
(princ)
