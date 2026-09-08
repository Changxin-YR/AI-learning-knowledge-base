
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

interface CompatDocument {
  name: string
}

const COMPAT_FILES: string[] = ['round7.txt', 'round7.md', 'round7.pdf', 'round7.docx', 'round7.pptx']

class DocumentPickerHandler implements MethodCallHandler {
  private readonly context: common.UIAbilityContext

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'listCompatDocuments') {
      this.listCompatDocuments().then((documents: CompatDocument[]) => result.success(documents)).catch((error: Error) => {
        result.error('compat_picker_failed', error.message, null)
      })
      return
    }
    if (call.method === 'readCompatDocument') {
      const name = call.argument('name') as string
      this.readCompatDocument(name).then((document: PickedDocument) => result.success(document)).catch((error: Error) => {
        result.error('compat_picker_failed', error.message, null)
      })
      return
    }
    if (call.method !== 'pickDocument') {
      result.notImplemented()
      return
    }
    this.pickDocument().then((document: PickedDocument | null) => result.success(document)).catch((error: Error) => {
      const code = error.message === 'PICKER_TIMEOUT' ? 'picker_unavailable' : 'picker_failed'
      result.error(code, error.message, null)
    })
  }

  private async pickDocument(): Promise<PickedDocument | null> {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 1
    options.fileSuffixFilters = ['.txt', '.md', '.pdf', '.docx', '.pptx']
    const uris = await Promise.race([
      new picker.DocumentViewPicker(this.context).select(options),
      new Promise<Array<string>>((_, reject) => setTimeout(() => reject(new Error('PICKER_TIMEOUT')), 2500))
    ])
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

  private async ensureCompatFiles(): Promise<void> {
    for (const name of COMPAT_FILES) {
      const target = `${this.context.filesDir}/${name}`
      try {
        fs.statSync(target)
        continue
      } catch (_) {
        // The fixture is copied into the app sandbox on first use.
      }
      const bytes = await this.context.resourceManager.getRawFileContent(name)
      const file = fs.openSync(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        fs.writeSync(file.fd, bytes.buffer as ArrayBuffer)
      } finally {
        fs.closeSync(file.fd)
      }
    }
  }

  private async listCompatDocuments(): Promise<CompatDocument[]> {
    await this.ensureCompatFiles()
    const names = fs.listFileSync(this.context.filesDir)
    return names
      .filter((name: string) => COMPAT_FILES.indexOf(name) >= 0)
      .map((name: string): CompatDocument => ({ name }))
  }

  private async readCompatDocument(name: string): Promise<PickedDocument> {
    if (COMPAT_FILES.indexOf(name) < 0 || name.includes('/') || name.includes('\\')) {
      throw new Error('Unsupported compatibility document')
    }
    await this.ensureCompatFiles()
    const path = `${this.context.filesDir}/${name}`
    const stat = fs.statSync(path)
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
    try {
      const bytes = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, bytes)
      return { name, bytes: new Uint8Array(bytes) }
    } finally {
      fs.closeSync(file.fd)
    }
  }
}
