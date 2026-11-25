import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Turns a face crop into an embedding vector using FaceNet-512 (TFLite).
/// Two crops of the same person produce vectors with high cosine similarity.
///
/// Model: facenet_512.tflite from shubham0204/FaceRecognition_With_FaceNet_Android
/// (Apache-2.0). Input [1, 160, 160, 3] float, standardized per image.
/// Output [1, 512].
class FaceEmbedder {
  FaceEmbedder._(this._interpreter, this._inputSize, this._embeddingSize);

  final Interpreter _interpreter;
  final int _inputSize;
  final int _embeddingSize;

  static const _modelAsset = 'assets/facenet_512.tflite';

  static Future<FaceEmbedder> load() async {
    Interpreter? interpreter;
    // The GPU is much faster for this model. Fall back to CPU if the phone's
    // GPU driver doesn't support it.
    try {
      final gpu = InterpreterOptions()..addDelegate(GpuDelegateV2());
      interpreter = await Interpreter.fromAsset(_modelAsset, options: gpu);
      debugPrint('FaceEmbedder: using GPU');
    } catch (e) {
      debugPrint('FaceEmbedder: GPU unavailable ($e), using CPU');
    }
    interpreter ??= await Interpreter.fromAsset(
      _modelAsset,
      options: InterpreterOptions()..threads = 4,
    );

    final inShape = interpreter.getInputTensor(0).shape;
    if (inShape.first != 1) {
      interpreter.resizeInputTensor(0, [1, inShape[1], inShape[2], inShape[3]]);
      interpreter.allocateTensors();
    }
    final inputSize = interpreter.getInputTensor(0).shape[1];
    final embeddingSize = interpreter.getOutputTensor(0).shape.last;
    debugPrint('FaceEmbedder: input $inputSize, output $embeddingSize');
    return FaceEmbedder._(interpreter, inputSize, embeddingSize);
  }

  /// Returns an L2-normalized embedding for [faceCrop].
  ///
  /// The face and its mirror image are both run through the model and the
  /// results averaged. This makes the embedding steadier between frames.
  List<double> embed(img.Image faceCrop) {
    final resized =
        (faceCrop.width == _inputSize && faceCrop.height == _inputSize)
        ? faceCrop
        : img.copyResize(
            faceCrop,
            width: _inputSize,
            height: _inputSize,
            interpolation: img.Interpolation.linear,
          );
    final a = _run(resized);
    final b = _run(img.flipHorizontal(resized.clone()));

    final sum = List<double>.generate(_embeddingSize, (i) => a[i] + b[i]);
    var norm = 0.0;
    for (final v in sum) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm == 0) norm = 1;
    return [for (final v in sum) v / norm];
  }

  /// L2-normalized model output for one image of the input size.
  Float32List _run(img.Image face) {
    final rgb = face.getBytes(order: img.ChannelOrder.rgb);
    final n = rgb.length;

    // Per-image standardization: x' = (x - mean) / std, as FaceNet expects.
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += rgb[i];
    }
    final mean = sum / n;
    var sq = 0.0;
    for (var i = 0; i < n; i++) {
      final d = rgb[i] - mean;
      sq += d * d;
    }
    final std = math.max(math.sqrt(sq / n), 1 / math.sqrt(n));

    final input = Float32List(n);
    for (var i = 0; i < n; i++) {
      input[i] = (rgb[i] - mean) / std;
    }
    final output = Float32List(_embeddingSize);
    _interpreter.run(input.buffer.asUint8List(), output.buffer);

    var norm = 0.0;
    for (final v in output) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < output.length; i++) {
        output[i] /= norm;
      }
    }
    return output;
  }

  void close() => _interpreter.close();
}
