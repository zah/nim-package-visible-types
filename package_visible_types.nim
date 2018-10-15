import macros

proc isPublic(n: NimNode): bool =
  n.kind == nnkPostfix and $(n[0]) == "*"

proc skipRefTypes(n: NimNode): NimNode =
  result = n
  if result.kind in {nnkRefTy, nnkPtrTy}:
    result = result[0]

iterator recordFields(typeDef: NimNode): (NimNode, NimNode) =
  if typeDef.len > 0:
    var traversalStack = @[(typeDef, 0)]
    while true:
      assert traversalStack.len > 0

      let (typeDef, idx) = traversalStack[^1]
      let n = typeDef[idx]
      inc traversalStack[^1][1]

      if idx == typeDef.len - 1:
        discard traversalStack.pop

      case n.kind
      of nnkRecWhen:
        for i in countdown(n.len - 1, 0):
          let branch = n[i]
          case branch.kind:
          of nnkElifBranch:
            traversalStack.add (branch[1], 0)
          of nnkElse:
            traversalStack.add (branch[0], 0)
          else:
            assert false

        continue

      of nnkRecCase:
        assert n.len > 0
        for i in countdown(n.len - 1, 1):
          let branch = n[i]
          case branch.kind
          of nnkOfBranch:
            traversalStack.add (branch[^1], 0)
          of nnkElse:
            traversalStack.add (branch[0], 0)
          else:
            assert false

        traversalStack.add (newTree(nnkRecCase, n[0]), 0)
        continue

      of nnkIdentDefs:
        let fieldType = n[^2]
        for i in 0 ..< n.len - 2:
          yield (n[i], fieldType)

      of nnkNilLit, nnkDiscardStmt, nnkCommentStmt:
        discard

      else:
        assert false

      if traversalStack.len == 0: break

macro packageTypes*(typesBlock: untyped): untyped =
  result = typesBlock

  var forwardedPublicTypes = newTree(nnkExportStmt)
  let initIdent = newTree(nnkPostfix, ident"*", ident"init")

  for n in typesBlock:
    case n.kind
    of nnkCommentStmt:
      continue

    of nnkImportStmt:
      for module in n:
        forwardedPublicTypes.add module

    of nnkTypeSection:
      for typeDef in n:
        var typeName = typeDef[0]

        if typeName.isPublic:
          typeName = typeName[1]
          forwardedPublicTypes.add typeName
        else:
          # We make all private types public, but we don't add them to
          # the list of forwarded exported types
          typeDef[0] = newTree(nnkPostfix, ident"*", typeName)

        if typeDef.len >= 3:
          var typ = typeDef[2]
          let isRef = typ.kind in {nnkPtrTy, nnkRefTy}
          if isRef: typ = typ[0]
          if typ.kind != nnkObjectTy: continue

          # Here, we start to generate an init proc for the type
          # proc init*(_: type T, ...): T = T(...)
          var initProcRes = newTree(nnkObjConstr, typeName)
          var initProc = newProc(
            name = initIdent,
            params = @[
              typeName, # the return type comes first
              newIdentDefs(ident"_", newTree(nnkBracketExpr, ident"type", typeName))
            ],
            body = initProcRes)

          for fieldName, fieldType in recordFields(typ[2]):
            var fieldName = fieldName
            let isPublic = fieldName.isPublic
            if isPublic: fieldName = fieldName[1]

            initProc.params.add newIdentDefs(fieldName, fieldType)
            initProcRes.add newTree(nnkExprColonExpr, fieldName, fieldName)

            if not isPublic:
              let fieldAsgnOp = ident($fieldName & "=")
              if isRef:
                result.add quote do:
                  template `fieldName`*(o: `typeName`): var `fieldType` =
                    o.`fieldName`

                  template `fieldAsgnOp`*(o: `typeName`, val: `fieldType`) =
                    o.`fieldName` = val
              else:
                result.add quote do:
                  template `fieldName`*(o: `typeName`): `fieldType` =
                    o.`fieldName`

                  template `fieldName`*(o: ptr `typeName`): var `fieldType` =
                    o.`fieldName`

                  template `fieldName`*(o: ref `typeName`): var `fieldType` =
                    o.`fieldName`

                  template `fieldName`*(o: var `typeName`): var `fieldType` =
                    o.`fieldName`

                  template `fieldAsgnOp`*(o: var `typeName`, val: `fieldType`) =
                    o.`fieldName` = val

          result.add initProc
    else:
      macros.error("packageVisibleTypes: please provide a block consisting " &
                   "only of type definitions and imports", n)

  result.add quote do:
    template forwardPublicTypes* = `forwardedPublicTypes`

  # echo result.repr
