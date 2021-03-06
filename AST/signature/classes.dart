import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/member.dart';

import '../comments.dart';
import '../naming.dart';
import 'constructors.dart';
import 'fields.dart';
import 'methods.dart';

class Classes {
  static String printClass(ClassElement element) {
    var implementWithInterface = element.isMixin || element.isAbstract;
    var name = Naming.nameWithTypeParameters(element, false);
    var code = new StringBuffer();
    code.writeln("");
    Comments.appendComment(code, element);
    //if (element.hasProtected == true || element.isPrivate == true)
    //  code.write("internal ");
    //if (element.isPublic == true)
    code.write("public ");
    if (element.isAbstract == true && !implementWithInterface)
      code.write("abstract ");
    if (element.hasSealed == true) code.write("sealed ");

    code.write("class ${name}");

    var generics = '';
    if (name.contains('<'))
      generics = name.substring(name.indexOf('<'), name.lastIndexOf('>') + 1);

    // Add base class, interfaces, mixin interfaces
    var hasBaseClass =
        element.supertype != null && element.supertype.name != "Object";
    var inheritions = new List<String>();
    if (hasBaseClass) {
      inheritions.add(Naming.className(element.supertype));
    }

    // Add interfaces
    for (var interface in element.interfaces) {
      inheritions.add(Naming.nameWithTypeArguments(interface, true));
    }

    // Add mixin interfaces
    for (var mxin in element.mixins) {
      inheritions.add(Naming.nameWithTypeArguments(mxin, true));
    }

    // Add superclasses of mixins as interfaces
    for (var mixinSuperclass in element.superclassConstraints.where((c) =>
        c.displayName != "@Object" &&
        c.displayName != "object" &&
        c.displayName != "Object")) {
      inheritions.add(Naming.nameWithTypeArguments(mixinSuperclass, true));
    }

    // add its interface if class is a mixin
    if (implementWithInterface) {
      inheritions.add(Naming.mixinInterfaceName(element));
    }

    if (inheritions.length > 0) code.write(" : " + inheritions.join(","));

    var inheritedType = '';
    // HACK: Inherited Generic Type Parameter
    // This is a hack because we should be applying this to the specific
    // methods its overriding, but seeing if I can get away with this for the moment.
    if (inheritions.length == 1) {
      var value = inheritions[0];
      if (value.contains('<'))
        inheritedType =
            value.substring(value.indexOf('<') + 1, value.indexOf('>'));
    }

    code.writeln("\n{");

    code.writeln("#region constructors");

    // Add constructors
    for (var constructor in element.constructors) {
      Constructors.printConstructor(code, constructor, generics);
    }
    code.writeln("#endregion\n");

    // Add fields and methods
    printFieldsAndMethods(code, element, implementWithInterface, inheritedType);

    code.writeln("}");
    return code.toString();
  }

  static void printFieldsAndMethods(StringBuffer code, ClassElement element,
      bool implementWithInterface, String inheritedType) {
    // Add mixin fields and method implementations
    code.writeln("#region inherited methods and fields");
    var overridenImplementations = new List<ClassMemberElement>();
    var implementedVariables = new List<ClassMemberElement>();

    // Add mixin implementations
    if (element.mixins.length > 0) {
      code.writeln("#region inherited from mixins");
      // Sort mixin because only the last implementation of a method is used in dart
      var sortedMixins = element.mixins.reversed;
      for (var implementedMixin in sortedMixins) {
        code.writeln("#region inherited from ${implementedMixin.name}");

        // Add the methods of the mixin and all its base methods
        code.writeln(implementedInstanceName(implementedMixin));

        addMixinImplementations(
            element,
            implementedMixin.name,
            implementedMixin,
            code,
            implementedVariables,
            overridenImplementations);
        code.writeln("#endregion\n");
      }
      code.writeln("#endregion\n");
    }

    // Add interface implementations
    var extendingClasses = element.interfaces.toList();
    extendingClasses
        .addAll(element.superclassConstraints.where((c) => c.name != "Object"));
    if (extendingClasses.length > 0) {
      code.writeln("#region inherited from interfaces");
      for (var implementedClass in extendingClasses.reversed) {
        code.writeln("#region inherited from ${implementedClass.name}");
        code.writeln(implementedInstanceName(implementedClass));
        addInterfaceImplementations(
            element,
            implementedClass.name,
            implementedClass,
            code,
            implementedVariables,
            overridenImplementations);
        code.writeln("#endregion\n");
      }
      code.writeln("#endregion\n");
    }
    code.writeln("#endregion\n");

    code.writeln("#region fields");
    // Add fields that are not already handled as implementation overrides
    for (var field
        in element.fields.where((f) => !overridenImplementations.contains(f))) {
      code.writeln(Fields.printField(field));
    }
    code.writeln("#endregion\n");

    code.writeln("#region methods");
    // Add methods that are not already handled as implementation overrides
    for (var method in element.methods.where((m) =>
        !overridenImplementations.any((x) => x.name == m.name) &&
        !implementedVariables.any((x) => x.name == m.name))) {
      code.writeln(Methods.printMethod(method, implementWithInterface,
          Methods.overridesParentBaseMethod(method, element), inheritedType));
    }
    code.writeln("#endregion");
  }

  static void addInterfaceImplementations(
      ClassElement element,
      String implementationInstanceName,
      InterfaceType implementedMixin,
      StringBuffer code,
      List<ClassMemberElement> implementedVariables,
      List<ClassMemberElement> overridenImplementations) {
    addImplementedFields(code, implementationInstanceName, implementedMixin,
        element, implementedVariables, overridenImplementations, null);
    addImplementedMethods(code, implementationInstanceName, implementedMixin,
        element, implementedVariables, overridenImplementations, null);

    for (var supertype in implementedMixin.element.allSupertypes.where((c) =>
        c.displayName != "@Object" &&
        c.displayName != "object" &&
        c.displayName != "Object")) {
      addInterfaceImplementations(element, implementationInstanceName,
          supertype, code, implementedVariables, overridenImplementations);
    }
  }

  static void addMixinImplementations(
      ClassElement element,
      String mixinInstanceName,
      InterfaceType implementedMixin,
      StringBuffer code,
      List<ClassMemberElement> implementedVariables,
      List<ClassMemberElement> overridenImplementations,
      [InterfaceType originalMixin = null]) {

    addImplementedFields(code, mixinInstanceName, implementedMixin, element,
        implementedVariables, overridenImplementations, originalMixin);
    addImplementedMethods(code, mixinInstanceName, implementedMixin, element,
        implementedVariables, overridenImplementations, originalMixin);
    for (var supertype in implementedMixin.element.superclassConstraints.where(
        (c) =>
            c.displayName != "@Object" &&
            c.displayName != "object" &&
            c.displayName != "Object")) {
      addMixinImplementations(element, mixinInstanceName, supertype, code,
          implementedVariables, overridenImplementations, implementedMixin);
    }
  }

  static String implementedInstanceName(InterfaceType element) {
    var implementedTypeName = element.name;
    var mxinNameWithTypes = Naming.nameWithTypeArguments(element, false);
    // Add instance of the implemented class
    // The implementations of the interface will call the methods provided by this instance
    return "private ${mxinNameWithTypes} ${implementedTypeName} = new ${mxinNameWithTypes}();";
  }

  static void addImplementedFields(
      StringBuffer code,
      String implementationInstanceName,
      InterfaceType implementedType,
      ClassElement implementingType,
      List<ClassMemberElement> addedByMixins,
      List<ClassMemberElement> addedByImplementations,
      InterfaceType originalMixin) {
    for (var implementedField in implementedType.element.fields.where((field) =>
        field.isPublic &&
        !addedByImplementations.any((existingMethod) =>
            existingMethod.displayName == field.displayName) &&
        !addedByMixins.any((existingMethod) =>
            existingMethod.displayName == field.displayName))) {
      // Store which methods are already implemented to avoid multiple declarations of the same method
      addedByMixins.add(implementedField);

      // Check if a field in this class overrides the implemented method
      // Use the method body of the overriding field in this case
      var overrideElement = implementingType.fields.firstWhere(
          (method) => method.name == implementedField.name,
          orElse: () => null);
      // Store the overriding field to avoid adding it again when adding the other fields
      if (overrideElement != null) addedByImplementations.add(overrideElement);

      code.writeln(
          // Pass the overriden element to get the correct field signature
          Fields.printImplementedField(implementedField, overrideElement,
              implementedType, implementationInstanceName, implementingType, originalMixin));
    }
  }

  static void addImplementedMethods(
      StringBuffer code,
      String implementationInstanceName,
      InterfaceType implementedType,
      ClassElement implementingType,
      List<ClassMemberElement> addedByMxins,
      List<ClassMemberElement> addByInterfaces,
      InterfaceType originalMixin) {
    for (var implementedMethod in implementedType.methods.where((method) =>
        method.isPublic &&
        !addByInterfaces.any((existingMethod) =>
            existingMethod.displayName == method.displayName) &&
        !addedByMxins.any((existingMethod) =>
            existingMethod.displayName == method.displayName))) {
      // Store which methods are already implemented to avoid multiple declarations of the same method
      addedByMxins.add(implementedMethod);

      // Check if a method in this class overrides the implemented method
      // Use the method body of the overriding method in this case
      var overridingMethod = implementingType.methods.firstWhere(
          (method) => method.name == implementedMethod.name,
          orElse: () => null);
      // Store the overriding method to avoid adding it again when adding the other methods
      if (overridingMethod != null) addByInterfaces.add(overridingMethod);

      code.writeln(Methods.printImplementedMethod(
          // Pass the overriden element to get the correct method modifiers
          overridingMethod != null ? overridingMethod : implementedMethod,
          implementationInstanceName,
          implementedType,
          overridingMethod,
          implementingType,
          originalMixin));
    }
  }

  static String printInterface(ClassElement element) {
    var name = Naming.nameWithTypeParameters(element, true);
    var code = new StringBuffer();
    code.writeln("");
    Comments.appendComment(code, element);

    if (element.hasProtected == true || element.isPrivate == true)
      code.write("internal ");
    if (element.isPublic == true) code.write("public ");

    code.write("interface ${name}{\n");

    for (var method in element.methods
        .where((method) => method.isPublic || method.hasProtected)) {
      var baseMethod = Methods.getBaseMethodInClass(method);
      code.writeln(
          Methods.methodSignature(baseMethod, method, null, false) + ";");
    }

    for (var field in element.fields
        .where((field) => field.isPublic || field.hasProtected)) {
      // if (field.displayName == 'clipBehavior' && name == 'IChipAttributes') {
      //   if (field is FieldMember) {
      //     var node = field.computeNode();
      //     node.toString();
      //   } else
      //   {
      //      var node = field.computeNode();
      //     node.toString();
      //   }
      // }
      var baseField = Fields.getBaseFieldInClass(field);
      code.writeln(Fields.getFieldSignature(baseField));
    }

    code.writeln("}");
    return code.toString();
  }
}
