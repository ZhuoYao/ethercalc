vm = require('vm')
fs = require("fs")
path = require("path")
jsdom = require("jsdom")
bootSC = fs.readFileSync(path.join(path.dirname(fs.realpathSync(__filename)) + '/SocialCalc.js'), 'utf8')
SC ?= {}

@include = ->
  SC._init = (snapshot, log, DB, room, io) ->
    if SC[room]?
      SC[room]._doClearCache()
      return SC[room]
    sandbox = vm.createContext(SocialCalc: null, ss: null, console: console, require: -> jsdom)
    vm.runInContext bootSC, sandbox
    SocialCalc = sandbox.SocialCalc
    SocialCalc.SaveEditorSettings = -> ""
    SocialCalc.CreateAuditString = -> ""
    SocialCalc.CalculateEditorPositions = ->
    SocialCalc.Popup.Types.List.Create = ->
    SocialCalc.Popup.Types.ColorChooser.Create = ->
    SocialCalc.Popup.Initialize = ->
    vm.runInContext 'ss = new SocialCalc.SpreadsheetControl', sandbox
    SocialCalc.RecalcInfo.LoadSheet = (ref) ->
      ref = ref.replace(/[^a-zA-Z0-9]+/g, "").toLowerCase()
      if SC[ref]
        serialization = SC[ref].CreateSpreadsheetSave()
        parts = SC[ref].DecodeSpreadsheetSave(serialization)
        SocialCalc.RecalcLoadedSheet(
          ref,
          serialization.substring(parts.sheet.start, parts.sheet.end),
          true # recalc
        )
      else
        SocialCalc.RecalcLoadedSheet(ref, "", true)
      return true

    ss = sandbox.ss
    delete ss.editor.StatusCallback.statusline
    div = SocialCalc.document.createElement('div')
    SocialCalc.document.body.appendChild div
    ss.InitializeSpreadsheetControl(div, 0, 0, 0)
    ss._room = room
    ss._doClearCache = -> SocialCalc.Formula.SheetCache.sheets = {}
    ss.editor.StatusCallback.EtherCalc = func: (editor, status, arg) ->
      return unless status is 'doneposcalc' and not ss.editor.busy
      newSnapshot = ss.CreateSpreadsheetSave()
      return if ss._snapshot is newSnapshot
      io.sockets.in("recalc.#{room}").emit 'data', {
        type: 'recalc'
        room: room
        snapshot: newSnapshot
        force: true
      }
      ss._snapshot = newSnapshot
      DB.multi()
        .set("snapshot-#{room}", newSnapshot)
        .del("log-#{room}")
        .bgsave()
        .exec => console.log "Regenerated snapshot for #{room}"
    parts = ss.DecodeSpreadsheetSave(snapshot) if snapshot
    if parts?.sheet
      ss.sheet.ResetSheet()
      ss.ParseSheetSave snapshot.substring(parts.sheet.start, parts.sheet.end)
    cmdstr = (line for line in log when not /^re(calc|display)$/.test(line)).join("\n")
    cmdstr += "\n" if cmdstr.length
    ss.context.sheetobj.ScheduleSheetCommands "set sheet defaulttextvalueformat text-wiki\n#{
      cmdstr
    }recalc\n", false, true
    return ss
  return SC
