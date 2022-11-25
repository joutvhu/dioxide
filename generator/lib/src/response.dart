import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';

DartType? getResponseType(DartType type) {
  return genericOf(type);
}

/// get types for `Map<String, List<User>>`, `A<B,C,D>`
List<DartType>? getResponseInnerTypes(DartType type) {
  final genericList = genericListOf(type);
  return genericList;
}

DartType? getResponseInnerType(DartType type) {
  final generic = genericOf(type);
  if (generic == null || typeChecker(Map).isExactlyType(type) || typeChecker(BuiltMap).isExactlyType(type)) {
    return type;
  }

  if (generic.isDynamic) return null;

  if (typeChecker(List).isExactlyType(type) || typeChecker(BuiltList).isExactlyType(type)) return generic;

  return getResponseInnerType(generic);
}

ConstantReader? getResponseTypeAnnotation(MethodElement method) {
  final annotation = typeChecker(dioxide.DioResponseType).firstAnnotationOf(method, throwOnUnresolved: false);
  if (annotation != null) return ConstantReader(annotation);
  return null;
}
