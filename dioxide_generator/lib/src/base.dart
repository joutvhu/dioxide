import 'dart:ffi';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';
import 'package:tuple/tuple.dart';

class DioxideOptions {
  final bool? autoCastResponse;

  DioxideOptions({this.autoCastResponse});

  DioxideOptions.fromOptions([BuilderOptions? options])
      : autoCastResponse = (options?.config['auto_cast_response']?.toString() ?? 'true') == 'true';
}

extension DartTypeStreamAnnotation on DartType {
  bool get isDartAsyncStream {
    final element = this.element == null ? null : this.element as ClassElement;
    if (element == null) {
      return false;
    }
    return element.name == 'Stream' && element.library.isDartAsync;
  }
}

String displayString(dynamic e, {bool withNullability = false}) {
  try {
    return e.getDisplayString(withNullability: withNullability);
  } catch (error) {
    if (error is TypeError) {
      return e.getDisplayString();
    } else {
      rethrow;
    }
  }
}

extension DartTypeExt on DartType {
  bool get isNullable => nullabilitySuffix == NullabilitySuffix.question;
}

extension ReferenceExt on Reference {
  Reference asNoNull() => refer('$symbol!');

  Reference asNoNullIf({required bool returnNullable}) => returnNullable ? this : asNoNull();

  Expression propertyIf({
    required bool thisNullable,
    required String name,
  }) =>
      thisNullable ? nullSafeProperty(name) : asNoNull().property(name);

  Expression conditionalIsNullIf({
    required bool thisNullable,
    required Expression whenFalse,
  }) =>
      thisNullable ? equalTo(literalNull).conditional(literalNull, whenFalse) : whenFalse;
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (T element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

TypeChecker typeChecker(Type type) => TypeChecker.fromRuntime(type);

DartType? genericOf(DartType type) {
  return type is InterfaceType && type.typeArguments.isNotEmpty ? type.typeArguments.first : null;
}

List<DartType>? genericListOf(DartType type) {
  return type is ParameterizedType && type.typeArguments.isNotEmpty ? type.typeArguments : null;
}

bool isBasicType(DartType? returnType) {
  if (returnType == null) {
    return false;
  }
  return typeChecker(String).isExactlyType(returnType) ||
      typeChecker(bool).isExactlyType(returnType) ||
      typeChecker(int).isExactlyType(returnType) ||
      typeChecker(double).isExactlyType(returnType) ||
      typeChecker(num).isExactlyType(returnType) ||
      typeChecker(Double).isExactlyType(returnType) ||
      typeChecker(Float).isExactlyType(returnType);
}

bool isBasicInnerType(DartType returnType) {
  var innnerType = genericOf(returnType);
  return isBasicType(innnerType);
}

Map<ParameterElement, ConstantReader> getAnnotations(MethodElement m, Type type) {
  var annot = <ParameterElement, ConstantReader>{};
  for (final p in m.parameters) {
    final a = typeChecker(type).firstAnnotationOf(p);
    if (a != null) {
      annot[p] = ConstantReader(a);
    }
  }
  return annot;
}

Tuple2<ParameterElement, ConstantReader>? getAnnotation(MethodElement m, Type type) {
  for (final p in m.parameters) {
    final a = typeChecker(type).firstAnnotationOf(p);
    if (a != null) {
      return Tuple2(p, ConstantReader(a));
    }
  }
  return null;
}

ConstantReader? getMethodAnnotationByType(MethodElement method, Type type) {
  final annot = typeChecker(type).firstAnnotationOf(method, throwOnUnresolved: false);
  if (annot != null) return ConstantReader(annot);
  return null;
}
