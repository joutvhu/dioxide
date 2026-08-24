import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
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
  return (<MethodElement>[...element.methods, ...element.mixins.expand((i) => i.methods)]).where((MethodElement m) {
    final methodAnnot = _getMethodAnnotation(m);
    return methodAnnot != null && m.isAbstract && (m.returnType.isDartAsyncFuture || m.returnType.isDartAsyncStream);
  });
}

/// Returns the [UseCallAdapter] annotation on [m], or null.
ConstantReader? getCallAdapterAnnotation(MethodElement m) {
  final annot = typeChecker(dioxide.UseCallAdapter).firstAnnotationOf(m, throwOnUnresolved: false);
  if (annot != null) return ConstantReader(annot);
  return null;
}

/// Generates the public method that delegates to the adapter, and the private
/// `_methodName` method that performs the actual HTTP call.
///
/// When [callAdapterType] is non-null the generator emits two methods:
///   1. A public override that calls `AdapterClass<T>().adapt(() => _methodName(...))`
///   2. A private `_methodName` that contains the real request logic.
///
/// When [callAdapterType] is null a single public override is emitted (existing behaviour).
List<Method> generateMethodWithAdapter(
  MethodElement m,
  Code Function(MethodElement m, ConstantReader httpMethod) generateRequest, {
  InterfaceType? callAdapterType,
}) {
  final httpMethod = _getMethodAnnotation(m);
  if (httpMethod == null) return [];

  if (callAdapterType == null) {
    final method = _buildMethod(m, m.displayName, httpMethod, generateRequest, isOverride: true);
    if (method == null) return [];
    return [method];
  }

  // With adapter: emit private impl + public adapter wrapper.
  final privateMethod = _buildMethod(m, '_${m.displayName}', httpMethod, generateRequest, isOverride: false);
  if (privateMethod == null) return [];

  final adapterMethod = _buildAdapterMethod(m, callAdapterType);
  return [privateMethod, adapterMethod];
}

/// Kept for backward compatibility — used by existing callers that don't need adapter support.
Method? generateMethod(MethodElement m, Code Function(MethodElement m, ConstantReader httpMethod) generateRequest) {
  final methods = generateMethodWithAdapter(m, generateRequest);
  return methods.isEmpty ? null : methods.first;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

Method? _buildMethod(
  MethodElement m,
  String name,
  ConstantReader httpMethod,
  Code Function(MethodElement m, ConstantReader httpMethod) generateRequest, {
  required bool isOverride,
}) {
  return Method((mm) {
    mm
      ..returns = refer(displayString(m.type.returnType, withNullability: true))
      ..name = name
      ..types.addAll(m.typeParameters.map((e) => refer(e.name)))
      ..modifier = m.returnType.isDartAsyncFuture ? MethodModifier.async : MethodModifier.asyncStar;

    if (isOverride) {
      mm.annotations.add(CodeExpression(Code('override')));
    }

    mm.requiredParameters.addAll(m.parameters.where((it) => it.isRequiredPositional).map((it) => Parameter((p) => p
      ..name = it.name
      ..named = it.isNamed
      ..type = refer(it.type.getDisplayString(withNullability: true)))));

    mm.optionalParameters
        .addAll(m.parameters.where((i) => i.isOptional || i.isRequiredNamed).map((it) => Parameter((p) => p
          ..required = (it.isNamed && it.type.nullabilitySuffix == NullabilitySuffix.none && !it.hasDefaultValue)
          ..name = it.name
          ..named = it.isNamed
          ..type = refer(it.type.getDisplayString(withNullability: true))
          ..defaultTo = it.defaultValueCode == null ? null : Code(it.defaultValueCode!))));

    mm.body = generateRequest(m, httpMethod);
  });
}

/// Builds the public override that wraps the private method with the adapter.
Method _buildAdapterMethod(MethodElement m, InterfaceType callAdapterType) {
  // The adapter's second type param is the adapted return type, e.g. Future<Result<T>>.
  // We use the method's declared return type as-is (the user wrote it).
  final adapterClassName = callAdapterType.element.name;

  // Collect the inner type T from the method's return type to instantiate the adapter.
  // e.g. Future<Result<User>> → the adapter is ResultAdapter<User>
  final innerType = _extractAdapterInnerType(m.returnType, callAdapterType);
  final adapterInstantiation = innerType != null ? '$adapterClassName<$innerType>()' : '$adapterClassName()';

  // Build argument list to forward to the private method.
  final positionalArgs = m.parameters
      .where((p) => p.isRequiredPositional || p.isOptionalPositional)
      .map((p) => p.name)
      .join(', ');
  final namedArgs = m.parameters
      .where((p) => p.isNamed)
      .map((p) => '${p.name}: ${p.name}')
      .join(', ');
  final allArgs = [positionalArgs, namedArgs].where((s) => s.isNotEmpty).join(', ');

  return Method((mm) {
    mm
      ..returns = refer(displayString(m.type.returnType, withNullability: true))
      ..name = m.displayName
      ..types.addAll(m.typeParameters.map((e) => refer(e.name)))
      ..modifier = MethodModifier.async
      ..annotations.add(CodeExpression(Code('override')));

    mm.requiredParameters.addAll(m.parameters.where((it) => it.isRequiredPositional).map((it) => Parameter((p) => p
      ..name = it.name
      ..named = it.isNamed
      ..type = refer(it.type.getDisplayString(withNullability: true)))));

    mm.optionalParameters
        .addAll(m.parameters.where((i) => i.isOptional || i.isRequiredNamed).map((it) => Parameter((p) => p
          ..required = (it.isNamed && it.type.nullabilitySuffix == NullabilitySuffix.none && !it.hasDefaultValue)
          ..name = it.name
          ..named = it.isNamed
          ..type = refer(it.type.getDisplayString(withNullability: true))
          ..defaultTo = it.defaultValueCode == null ? null : Code(it.defaultValueCode!))));

    mm.body = Code('return $adapterInstantiation.adapt(() => _${m.displayName}($allArgs));');
  });
}

/// Extracts the inner type `T` from the method return type given the adapter's
/// second type parameter template.
///
/// e.g. adapter is `ResultAdapter<T>` with `T = Future<Result<T>>`,
/// method returns `Future<Result<User>>` → returns `"User"`.
///
/// Falls back to null if extraction fails (adapter will be instantiated without type arg).
String? _extractAdapterInnerType(DartType methodReturnType, InterfaceType callAdapterType) {
  // The adapter's superclass is CallAdapter<R, T>.
  // typeArguments[1] is T (the adapted return type template), e.g. Future<Result<dynamic>>
  final adaptedTemplate = callAdapterType.superclass?.typeArguments.elementAtOrNull(1);
  if (adaptedTemplate == null) return null;

  final templateStr = adaptedTemplate.getDisplayString(withNullability: false);
  final actualStr = methodReturnType.getDisplayString(withNullability: false);

  // Replace 'dynamic' placeholder in template with a regex group to extract the real type.
  final pattern = RegExp(RegExp.escape(templateStr).replaceAll('dynamic', r'([\w<>?, ]+)'));
  final match = pattern.firstMatch(actualStr);
  if (match != null && match.groupCount > 0) {
    return match.group(1);
  }
  return null;
}

ConstantReader? _getMethodAnnotation(MethodElement method) {
  for (final type in _methodsAnnotations) {
    final annot = typeChecker(type).firstAnnotationOf(method, throwOnUnresolved: false);
    if (annot != null) return ConstantReader(annot);
  }
  return null;
}
