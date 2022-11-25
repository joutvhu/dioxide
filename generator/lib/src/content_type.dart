import 'package:analyzer/dart/element/element.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';

ConstantReader? getContentTypeAnnotation(MethodElement method) {
  final multipart = _getMultipartAnnotation(method);
  final formUrlEncoded = _getFormUrlEncodedAnnotation(method);

  if (multipart != null && formUrlEncoded != null) {
    throw InvalidGenerationSourceError('Two content-type annotation on one request ${method.name}');
  }

  return multipart ?? formUrlEncoded;
}

ConstantReader? _getMultipartAnnotation(MethodElement method) {
  final annotation = typeChecker(dioxide.MultiPart).firstAnnotationOf(method, throwOnUnresolved: false);
  if (annotation != null) return ConstantReader(annotation);
  return null;
}

ConstantReader? _getFormUrlEncodedAnnotation(MethodElement method) {
  final annotation = typeChecker(dioxide.FormUrlEncoded).firstAnnotationOf(method, throwOnUnresolved: false);
  if (annotation != null) return ConstantReader(annotation);
  return null;
}
