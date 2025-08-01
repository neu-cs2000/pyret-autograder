include file("../src/core.arr")
include file("../src/utils.arr")
include file("../src/grading.arr")

data MockBlock:
  | blocker1
  | blocker2
end

fun strip-ctx<A, B, C>(output :: GradingOutput<A, B, C>) -> GradingOutput<A, B, Nothing>:
  doc: "replace ctx from the NodeResult so we can compare for structural equality"
  {
    aggregated: output.aggregated,
    trace:
      {(x):
        x.{ result: cases (NodeResult) x.result:
          | executed(outcome, info, ctx) => executed(outcome, info, nothing)
          | skipped(id, ctx) => skipped(id, nothing)
        end }}
      ^ output.trace.map
  }
where:
  strip-ctx({
    aggregated: [list:],
    trace: [list: {id: "foo1", result: executed(emit(score(0.5)), nothing, {(x): x})},
                  {id: "foo2", result: skipped("bar", {(x): x + 1})}]
  }) is {
    aggregated: [list:],
    trace: [list: {id: "foo1", result: executed(emit(score(0.5)), nothing, nothing)},
                  {id: "foo2", result: skipped("bar", nothing)}]
  }
end

check "grading: control flow":
  fun dummy-agg(info :: String):
    agg-test("", "", 0, test-ok(0, output-text(info), none))
  end

  fun simple-aggregator(node-result :: NodeResult):
    cases (NodeResult) node-result:
      | executed(outcome, info, ctx) =>
        str-outcome = cases (Outcome) outcome:
          | block(reason) => "(block " + to-repr(reason) + ")"
          | noop => "(noop)"
          | emit(grading-result) =>
            str-gr = cases (GradingResult) grading-result:
              | score(earned) => "(score " + to-repr(earned) + ")"
              | artifact(path) => "(artifact " + path + ")"
            end
            "(emit " + str-gr + ")"
          | internal-error(err) =>
            "(internal-error " + err.to-string() + ")"
        end
        "(executed (info " + to-repr(info) + ") (outcome " + str-outcome + "))"
      | skipped(id, ctx) => "(skipped " + id + ")"
    end
    ^ dummy-agg
    ^ some
  end

  fun mk-mock-grader(id, deps, runner) -> Grader:
    {
      id: id,
      deps: deps,
      run: lam():
        {runner(); nothing}
      end,
      to-aggregate: simple-aggregator
    }
  end

  grade(
    [list:
      mk-mock-grader("guard_1", [list:], {(): block(blocker1) }),
      mk-mock-grader("guard_2", [list: "guard_1"], {(): noop }),
      mk-mock-grader("test_1", [list: "guard_2"], {(): emit(score(1)) })])
    ^ strip-ctx
  is
  {
    aggregated: [list: "(executed (info nothing) (outcome (block blocker1)))",
                       "(skipped guard_1)",
                       "(skipped guard_1)"].map(dummy-agg),
    trace: [list: {id: "guard_1", result: executed(block(blocker1), nothing, nothing)},
                  {id: "guard_2", result: skipped("guard_1", nothing)},
                  {id: "test_1", result: skipped("guard_1", nothing)}]
  }

  grade(
    [list:
      mk-mock-grader("guard_1", [list:], {(): noop }),
      mk-mock-grader("guard_2", [list: "guard_1"], {(): block(blocker2) }),
      mk-mock-grader("test_1", [list: "guard_2"], {(): emit(score(1)) })])
    ^ strip-ctx
  is
  {
    aggregated: [list: "(executed (info nothing) (outcome (noop)))",
                       "(executed (info nothing) (outcome (block blocker2)))",
                       "(skipped guard_2)"].map(dummy-agg),
    trace: [list: {id: "guard_1", result: executed(noop, nothing, nothing)},
                  {id: "guard_2", result: executed(block(blocker2), nothing, nothing)},
                  {id: "test_1", result: skipped("guard_2", nothing)}]
  }

  grade(
    [list:
      mk-mock-grader("guard_1", [list:], {(): noop }),
      mk-mock-grader("guard_2", [list: "guard_1"], {(): noop }),
      mk-mock-grader("test_1", [list: "guard_2"], {(): emit(score(1)) })])
    ^ strip-ctx
  is
  {
    aggregated: [list: "(executed (info nothing) (outcome (noop)))",
                       "(executed (info nothing) (outcome (noop)))",
                       "(executed (info nothing) (outcome (emit (score 1))))"].map(dummy-agg),
    trace: [list: {id: "guard_1", result: executed(noop, nothing, nothing)},
                  {id: "guard_2", result: executed(noop, nothing, nothing)},
                  {id: "test_1", result: executed(emit(score(1)), nothing, nothing)}]
  }
end

check "grading: aggregators":
  fun tmpl(node-result):
    cases (NodeResult) node-result:
      | executed(outcome, info, ctx) =>
        cases (Outcome) outcome:
          | block(reason) => ...
          | noop => ...
          | emit(grading-result) =>
            cases (GradingResult) grading-result:
              | score(earned) => ...
              | artifact(path) => ...
            end
          | internal-error(err) => ...
        end
      | skipped(skip-id, ctx) => ...
    end
  end

  fun guard-aggregator(id, node-result):
    cases (NodeResult) node-result:
      | executed(outcome, info, ctx) =>
        cases (Outcome) outcome:
          | block(reason) =>
            guard-blocked(output-text("blocked"), some(output-text(info)))
          | noop => guard-passed
          | else => raise("invalid")
        end
      | skipped(skip-id, ctx) => guard-skipped(skip-id)
    end
    ^ agg-guard(id, "Guard", _)
    ^ some
  end

  fun test-aggregator(id, node-result):
    cases (NodeResult) node-result:
      | executed(outcome, info, ctx) =>
        cases (Outcome) outcome:
          | emit(grading-result) =>
            cases (GradingResult) grading-result:
              | score(earned) =>
                test-ok(earned, output-text("got score"), some(output-text(info)))
              | else => raise("invalid")
            end
          | else => raise("invalid")
        end
      | skipped(skip-id, ctx) => test-skipped(skip-id)
    end
    ^ agg-test(id, "Test", 1, _)
    ^ some
  end

  fun artifact-aggregator(id, node-result):
    cases (NodeResult) node-result:
      | executed(outcome, info, ctx) =>
        cases (Outcome) outcome:
          | emit(grading-result) =>
            cases (GradingResult) grading-result:
              | artifact(path) => art-ok(path, some(info))
              | else => raise("invalid")
            end
          | else => raise("invalid")
        end
      | skipped(skip-id, ctx) => art-skipped(skip-id)
    end
    ^ agg-artifact(id, "Artifact", none, _)
    ^ some
  end

  passing-guard-grader = {
    id: "guard",
    deps: [list:],
    run: {(): {noop; "passing info"}},
    to-aggregate: guard-aggregator("guard", _)
  }

  failing-guard-grader = {
    id: "guard",
    deps: [list:],
    run: {(): {block(blocker1); "block info"}},
    to-aggregate: guard-aggregator("guard", _)
  }

  dependent-guard = {
    id: "dep-guard",
    deps: [list: "guard"],
    run: {(): {noop; nothing}},
    to-aggregate: guard-aggregator("dep-guard", _)
  }

  scorer = {
    id: "scorer",
    deps: [list: "guard"],
    run: {(): {emit(score(1)); "score info"}},
    to-aggregate: test-aggregator("scorer", _)
  }

  artist = {
    id: "artist",
    deps: [list: "guard"],
    run: {(): {emit(artifact("/path/to/file")); "artifact info"}},
    to-aggregate: artifact-aggregator("artist", _)
  }

  grade([list: passing-guard-grader, dependent-guard]).aggregated
  is
  [list: agg-guard("guard", "Guard", guard-passed),
         agg-guard("dep-guard", "Guard", guard-passed)]

  grade([list: failing-guard-grader, dependent-guard]).aggregated
  is
  [list: agg-guard("guard", "Guard", guard-blocked(output-text("blocked"), some(output-text("block info")))),
         agg-guard("dep-guard", "Guard", guard-skipped("guard"))]

  grade([list: passing-guard-grader, scorer]).aggregated
  is
  [list: agg-guard("guard", "Guard", guard-passed),
         agg-test("scorer", "Test", 1, test-ok(1, output-text("got score"), some(output-text("score info"))))]

  grade([list: failing-guard-grader, scorer]).aggregated
  is
  [list: agg-guard("guard", "Guard", guard-blocked(output-text("blocked"), some(output-text("block info")))),
         agg-test("scorer", "Test", 1, test-skipped("guard"))]

  grade([list: passing-guard-grader, artist]).aggregated
  is
  [list: agg-guard("guard", "Guard", guard-passed),
         agg-artifact("artist", "Artifact", none, art-ok("/path/to/file", some("artifact info")))]

  grade([list: failing-guard-grader, artist]).aggregated
  is
  [list: agg-guard("guard", "Guard", guard-blocked(output-text("blocked"), some(output-text("block info")))),
         agg-artifact("artist", "Artifact", none, art-skipped("guard"))]

end

