import MaterialX
import MaterialXMetalShaders

public extension GraphStitcher {
    /// `plan` with each largest constant-only subgraph (no shading context, no textures) evaluated once on the GPU and
    /// replaced by one parameter named `<node>#folded`, as #30-Q1 chose. Constants inside a folded subgraph are no
    /// longer editable by their original names; their slots stay in ``GraphPlan/parameterData`` but nothing reads
    /// them, and they are removed from ``GraphPlan/parameters``.
    func foldingConstants(_ plan: GraphPlan) throws -> GraphPlan {
        let calls = plan.calls
        var isConstant = [Bool](repeating: false, count: calls.count)
        var consumers = [[Int]](repeating: [], count: calls.count)
        for (index, call) in calls.enumerated() {
            isConstant[index] = call.arguments.allSatisfy { operand in
                switch operand {
                case .parameters: true
                case let .call(argument): isConstant[argument]
                case .context, .textures, .surface: false
                }
            }
            for case let .call(argument) in call.arguments {
                consumers[argument].append(index)
            }
        }
        let foldable: Set<ValueType> = [.float, .vector2, .vector3, .vector4, .color3, .color4]
        // Roots: constant values that something non-constant reads. Bare parameter reads are already as cheap as a
        // folded value.
        let roots = calls.indices.filter { index in
            guard isConstant[index], let type = calls[index].valueType, foldable.contains(type),
                  !calls[index].function.hasPrefix("mx_parameter_") else { return false }
            return consumers[index].contains { !isConstant[$0] }
        }
        guard !roots.isEmpty else { return plan }

        var result = plan
        var replacements: [Int: GraphPlan.Operand] = [:]
        for root in roots {
            let type = calls[root].valueType ?? .float
            let value = try evaluateConstant(root, of: plan, type: type)
            // A fresh pointer chain to the new slot keeps the folded read independent of the old chain.
            let slot = result.parameterData.count
            result.parameterData.append(value)
            var pointer = GraphPlan.Operand.parameters
            for _ in 0..<slot {
                result.calls.append(.init(function: "mx_parameter_next", arguments: [pointer]))
                pointer = .call(result.calls.count - 1)
            }
            result.calls.append(.init(function: "mx_parameter_" + (try type.metalSuffix()), arguments: [pointer], origin: (calls[root].origin ?? "n\(root)") + "#folded", valueType: type))
            replacements[root] = .call(result.calls.count - 1)
            result.parameters.append(.init(name: (calls[root].origin ?? "n\(root)") + "#folded", type: type, slot: slot, slotCount: 1))
        }
        for index in result.calls.indices {
            result.calls[index].arguments = result.calls[index].arguments.map { operand in
                if case let .call(argument) = operand, let replacement = replacements[argument] {
                    return replacement
                }
                return operand
            }
        }
        result.calls = Self.reachableInOrder(result.calls, from: plan.calls.count - 1)
        // Parameter readers are tagged with their parameter's name; parameters with no reader left are dropped.
        let read = Set(result.calls.compactMap { call in call.function.hasPrefix("mx_parameter_") && call.function != "mx_parameter_next" ? call.origin : nil })
        result.parameters = result.parameters.filter { read.contains($0.name) }
        return result
    }

    /// Runs the calls `root` depends on as a separate graph and returns its value in parameter-slot form.
    private func evaluateConstant(_ root: Int, of plan: GraphPlan, type: ValueType) throws -> SIMD4<Float> {
        var calls = Self.reachableInOrder(plan.calls, from: root)
        calls.append(.init(function: "mx_output_" + (try type.metalSuffix()), arguments: [.call(calls.count - 1), .context, .parameters, .textures]))
        let subplan = GraphPlan(functionName: "mx_fold_\(abs(plan.topologyKey.hashValue))_\(root)", outputType: type, calls: calls, parameters: [], parameterData: plan.parameterData)
        var stitcher = self
        stitcher.foldConstants = false
        return try stitcher.stitch(subplan).evaluate(at: [.zero]).first ?? .zero
    }

    /// The calls `output` depends on (and `output` itself, last), in an order where every call comes after its
    /// arguments, with operands renumbered.
    static func reachableInOrder(_ calls: [GraphPlan.Call], from output: Int) -> [GraphPlan.Call] {
        var order: [Int] = []
        var state = [UInt8](repeating: 0, count: calls.count) // 0 new, 1 in progress, 2 done
        var stack: [(index: Int, expanded: Bool)] = [(output, false)]
        while let (index, expanded) = stack.popLast() {
            if expanded {
                state[index] = 2
                order.append(index)
                continue
            }
            guard state[index] == 0 else { continue }
            state[index] = 1
            stack.append((index, true))
            for case let .call(argument) in calls[index].arguments.reversed() where state[argument] == 0 {
                stack.append((argument, false))
            }
        }
        let newIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order.map { index in
            var call = calls[index]
            call.arguments = call.arguments.map { operand in
                if case let .call(argument) = operand, let mapped = newIndex[argument] {
                    return .call(mapped)
                }
                return operand
            }
            return call
        }
    }
}
