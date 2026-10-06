; Extra steps for the companion's NSIS installer (tauri.conf.json
; bundle.windows.nsis.installerHooks).

!macro NSIS_HOOK_POSTUNINSTALL
  ; Remove "Start with Windows" (tauri-plugin-autostart writes it under the
  ; app's name). Settings in %APPDATA%\Soapstone are kept, since they hold the
  ; install's token; the installer notice says how to remove them.
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Soapstone"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "soapstone-companion"
!macroend
