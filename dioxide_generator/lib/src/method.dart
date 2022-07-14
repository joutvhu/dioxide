import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';

final _methodsAnnotations = const [
  dioxide.GetRequest,
  dioxide.PostRequest,
  dioxide.DeleteRequest,
  dioxide.PutRequest,
  dioxide.PatchRequest,
  dioxide.HeadRequest,
  dioxide.OptionsRequest,
  dioxide.Method,
];

Iterable<MethodElement> getMethodElements(ClassElement element) {
  return (<MethodElement>[...element.methods, ...element.mixins.expand((i) => i.methods)])
      .where((MethodElement m) {
    final methodAnnot = _getMethodAnnotation(m);
    return methodAnnot != null && m.isAbstract && (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
  });
}

Method? generateMethod(MethodElement m, Code Function(MethodElement m, ConstantReader httpMethod) _generateRequest) {
  final httpMehod = _getMethodAnnotation(m);
  if (httpMehod == null) {
    return null;
  }

  return Method((mm) {
    mm
      ..returns = refer(displayString(m.type.returnType, withNullability: true))
      ..name = m.displayName
      ..types.addAll(m.typeParameters.map((e) => refer(e.name)))
      ..modifier = m.returnType.isDartAsyncFuture ? MethodModifier.async : MethodModifier.asyncStar
      ..annotations.add(CodeExpression(Code('override')));

    /// required parameters
    mm.requiredParameters.addAll(m.parameters.where((it) => it.isRequiredPositional).map((it) => Parameter((p) => p
      ..name = it.name
      ..named = it.isNamed)));

    /// optional positional or named parameters
    mm.optionalParameters
        .addAll(m.parameters.where((i) => i.isOptional || i.isRequiredNamed).map((it) => Parameter((p) => p
          ..required = (it.isNamed && it.type.nullabilitySuffix == NullabilitySuffix.none && !it.hasDefaultValue)
          ..name = it.name
          ..named = it.isNamed
          ..defaultTo = it.defaultValueCode == null ? null : Code(it.defaultValueCode!))));
    mm.body = _generateRequest(m, httpMehod);
  });
}

ConstantReader? _getMethodAnnotation(MethodElement method) {
  for (final type in _methodsAnnotations) {
    final annot = typeChecker(type).firstAnnotationOf(method, throwOnUnresolved: false);
    if (annot != null) return ConstantReader(annot);
  }
  return null;
}
