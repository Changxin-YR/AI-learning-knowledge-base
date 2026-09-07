
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { MethodChannel, MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    const channel = new MethodChannel(flutterEngine.getDartExecutor(), 'knowflow/file_picker')
    channel.setMethodCallHandler(new DocumentPickerHandler(this.context))
  }
}

interface PickedDocument {
  name: string
  bytes: Uint8Array
}

class DocumentPickerHandler implements MethodCallHandler {
  private readonly context: common.UIAbilityContext

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'pickDocument') {
      result.notImplemented()
      return
    }
    this.pickDocument().then((document: PickedDocument | null) => result.success(document)).catch((error: Error) => {
      result.error('picker_failed', error.message, null)
    })
  }

  private async pickDocument(): Promise<PickedDocument | null> {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 1
    options.fileSuffixFilters = ['.txt', '.md', '.pdf', '.docx', '.pptx']
    const uris = await new picker.DocumentViewPicker(this.context).select(options)
    if (uris.length === 0) return null
    const uri = uris[0]
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    try {
      const stat = fs.statSync(uri)
      const bytes = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, bytes)
      const rawName = uri.split('/').pop() ?? 'document'
      return { name: decodeURIComponent(rawName.split('?')[0]), bytes: new Uint8Array(bytes) }
    } finally {
      fs.closeSync(file.fd)
    }
  }
}
