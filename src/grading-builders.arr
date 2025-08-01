include either
include file("./core.arr")
include file("./grading.arr")

provide:
  type ComboAggregate,
  type GuardCheck,
  type GuardFormat,
  mk-guard,

  type ScorerRunner,
  type ScorerFormat,
  type ScorerWeight,
  mk-scorer,
  mk-simple-scorer
end

# first element in the tuple represents general output
# second element allows optionally specifying more information to course staff
#   only
type ComboAggregate = {AggregateOutput; Option<AggregateOutput>}

type GuardCheck<BlockReason> = (-> Option<BlockReason>) # TODO: internal error?
type GuardFormat<BlockReason> = (BlockReason -> ComboAggregate)

fun mk-guard<BlockReason, C>(
  id :: Id,
  deps :: List<Id>,
  checker :: GuardCheck<BlockReason>,
  name :: String,
  format :: GuardFormat<BlockReason>
) -> Grader<BlockReason, Nothing, C>:
  {
    id: id,
    deps: deps,
    run: lam():
      cases (Option) checker():
        | none => {noop; nothing}
        | some(reason) => {block(reason); nothing}
      end
    end,
    to-aggregate: lam(result :: GraderResult<BlockReason, Nothing, C>) -> Option<AggregateResult>:
      cases (NodeResult) result:
        | executed(outcome, _, _) =>
          cases (Outcome) outcome:
            | noop => guard-passed
            | block(reason) =>
              {general; staff} = format(reason)
              guard-blocked(general, staff)
            | else => raise("INVARIANT VIOLATED: unexpected outcome")
          end
        | skipped(skip-id, _) => guard-skipped(skip-id)
      end
      ^ agg-guard(id, name, _)
      ^ some
    end
  }
end

type ScorerRunner<Info> = (-> Either<{NormalizedNumber; Info}, InternalError>)
type ScorerFormat<Info> = (NormalizedNumber, Info -> ComboAggregate)
type ScorerWeight = (NormalizedNumber, Number -> Number)

fun mk-scorer<Info, C>(
  id :: Id,
  deps :: List<Id>,
  scorer :: ScorerRunner<Info>,
  name :: String,
  max-score :: Number,
  calc-score :: ScorerWeight,
  format :: ScorerFormat<Info>
) -> Grader<Nothing, Option<Info>, C>:
  INTERNAL-ERROR = "An interal error occured while running this test; " +
                   "please report this to course staff."
  {
    id: id,
    deps: deps,
    run: lam():
      cases (Either) scorer():
        | left({num; info}) => {emit(score(num)); some(info)}
        | right(err) => {internal-error(err); none}
      end
    end,
    to-aggregate: lam(result :: GraderResult<Nothing, Option<Info>, C>) -> Option<AggregateResult>:
      cases (NodeResult) result:
        | executed(outcome, info, _) =>
          cases (Outcome) outcome:
            | emit(res) =>
              cases (GradingResult) res block:
                | score(num) =>
                  shadow info = cases (Option) info:
                    | some(shadow info) => info
                    | none => raise("INVARIANT VIOLATED: missing score's info")
                  end
                  realized-score = calc-score(num, max-score)
                  {general; staff} = format(num, info)
                  test-ok(realized-score, general, staff)
                | else => raise("INVARIANT VIOLATED: scorer emitted non-score")
              end
            | internal-error(err) =>
              general = output-markdown(INTERNAL-ERROR)
              err-str = err.to-string()
              staff = output-text(err-str) ^ some
              test-ok(0, general, staff)
            | else => raise("INVARIANT VIOLATED: unexpected outcome")
          end
        | skipped(skip-id, _) => test-skipped(skip-id)
      end
      ^ agg-test(id, name, max-score, _)
      ^ some
    end
    # TODO: to-repl
  }
end

fun mk-simple-scorer<Info, C>(
  id :: Id,
  deps :: List<Id>,
  scorer :: ScorerRunner<Info>,
  name :: String,
  max-score :: Number,
  format :: ScorerFormat<Info>
) -> Grader<Nothing, Option<Info>, C>:
  calculator = lam(val, max):
    val * max
  end
  mk-scorer(id, deps, scorer, name, max-score, calculator, format)
end

fun make-artist<Info, C>(id :: Id, deps :: List<Id>) -> Nothing:
  nothing
end

