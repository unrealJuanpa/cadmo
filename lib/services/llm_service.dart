import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:llama_cpp_dart/src/llama_cpp.dart';

class LLMManager {
  static final LLMManager _instance = LLMManager._internal();
  factory LLMManager() => _instance;
  LLMManager._internal();

  llama_cpp? _lib;
  Pointer<Void>? _model;
  Pointer<Void>? _ctx;
  Pointer<Void>? _vocab;
  Pointer<Void>? _sampler;
  bool _initialized = false;

  Future<void> initModel(String modelFileName, {int nGpuLayers = 99}) async {
    if (_initialized) return;

    int nPredict = 32768;

    final docDir = await getApplicationDocumentsDirectory();
    final cadmoDir = Directory(join(docDir.path, 'Cadmo'));
    final modelsDir = Directory(join(cadmoDir.path, 'Models'));

    final modelPath = join(modelsDir.path, modelFileName);

    String libPath;
    if (Platform.isMacOS) libPath = join(cadmoDir.path, 'libllama.dylib');
    else if (Platform.isLinux) libPath = join(cadmoDir.path, 'libllama.so');
    else if (Platform.isWindows) libPath = join(cadmoDir.path, 'libllama.dll');
    else throw UnsupportedError('OS no soportado');

    final ggm = DynamicLibrary.open('libggml.dylib');
    _lib = llama_cpp(DynamicLibrary.open('libllama.dylib'));
    _lib!.llama_backend_init();

    var modelParams = _lib!.llama_model_default_params();
    modelParams.n_gpu_layers = nGpuLayers;

    final modelPathPtr = modelPath.toNativeUtf8().cast<Char>();
    _model = _lib!.llama_load_model_from_file(modelPathPtr, modelParams) as Pointer<Void>?;
    malloc.free(modelPathPtr);

    if (_model!.address == 0) throw Exception("No se pudo cargar el modelo");

    _vocab = _lib!.llama_model_get_vocab(_model as Pointer<llama_model>) as Pointer<Void>?;

    var ctxParams = _lib!.llama_context_default_params();
    ctxParams.n_ctx = nPredict;
    ctxParams.n_batch = 128;
    ctxParams.no_perf = false;

    _ctx = _lib!.llama_new_context_with_model(_model as Pointer<llama_model>, ctxParams) as Pointer<Void>?;
    if (_ctx!.address == 0) throw Exception("Error al crear el contexto");

    var sparams = _lib!.llama_sampler_chain_default_params();
    sparams.no_perf = false;
    _sampler = _lib!.llama_sampler_chain_init(sparams) as Pointer<Void>?;
    _lib!.llama_sampler_chain_add(_sampler! as Pointer<llama_sampler>, _lib!.llama_sampler_init_greedy());

    _initialized = true;
  }

  /// Stream de tokens generado en tiempo real
  Stream<String> ai_interact_stream(List<Map<String, String>> conversation) async* {
    if (!_initialized) throw Exception("El modelo no ha sido inicializado.");

    int nPredict = 32768;

    final prompt = StringBuffer();
    for (var msg in conversation) {
      if (msg['role'] == 'user') prompt.write('<|User|>${msg['content']}<|Assistant|><think>\n');
      else if (msg['role'] == 'assistant') prompt.write(msg['content']);
    }
    final promptStr = '<|begin_of_sentence|>${prompt.toString()}';

    final promptPtr = promptStr.toNativeUtf8().cast<Char>();
    final nPrompt = -_lib!.llama_tokenize(_vocab! as Pointer<llama_vocab>, promptPtr, promptStr.length, nullptr, 0, true, true);

    final tokens = malloc<llama_token>(nPrompt);
    if (_lib!.llama_tokenize(_vocab! as Pointer<llama_vocab>, promptPtr, promptStr.length, tokens, nPrompt, true, true) < 0) {
      malloc.free(promptPtr);
      malloc.free(tokens);
      throw Exception("Error al tokenizar el prompt");
    }
    malloc.free(promptPtr);

    var batch = _lib!.llama_batch_get_one(tokens, nPrompt);
    final tokenPtr = malloc<llama_token>();

    for (int nPos = 0; nPos + batch.n_tokens < nPrompt + nPredict;) {
      if (_lib!.llama_decode(_ctx! as Pointer<llama_context>, batch) != 0) break;
      nPos += batch.n_tokens;

      int newTokenId = _lib!.llama_sampler_sample(_sampler! as Pointer<llama_sampler>, _ctx! as Pointer<llama_context>, -1);
      if (_lib!.llama_token_is_eog(_vocab! as Pointer<llama_vocab>, newTokenId)) break;

      final buf = malloc<Char>(128);
      int n = _lib!.llama_token_to_piece(_vocab! as Pointer<llama_vocab>, newTokenId, buf, 128, 0, true);
      if (n < 0) {
        malloc.free(buf);
        break;
      }

      final piece = String.fromCharCodes(buf.cast<Uint8>().asTypedList(n));
      malloc.free(buf);

      tokenPtr.value = newTokenId;
      batch = _lib!.llama_batch_get_one(tokenPtr, 1);

      yield piece; // cada token se emite aquí
    }

    malloc.free(tokenPtr);
    malloc.free(tokens);
  }

  void dispose_model() {
    if (!_initialized) return;

    _lib!.llama_sampler_free(_sampler! as Pointer<llama_sampler>);
    _lib!.llama_free(_ctx! as Pointer<llama_context>);
    _lib!.llama_free_model(_model! as Pointer<llama_model>);
    _lib!.llama_backend_free();

    _sampler = null;
    _ctx = null;
    _model = null;
    _vocab = null;
    _initialized = false;
  }
}
