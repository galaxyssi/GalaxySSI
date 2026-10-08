package com.galaxyssi.chat

internal object CollaborationPredictionProtocol {
    fun instructions() = """
        For consequential uncertain choices, build a scoped task_environment_model from observed/assumed/unknown state,
        competing transitions, confounders and an explicit defer option. Preregister observable expectations before acting;
        use action_forecast prediction_mode=qualitative when probabilities are unknown. Do not invent numeric confidence or utility.
        Compare benefit, resources, uncertainty, reversibility and risk, not confidence alone.
        Select the action yourself and bind prediction_work:{forecast:<exact ref>} to its named existing DAG work/member.
        Recheck preconditions on execution/resume; an old forecast never grants permission or proves the environment unchanged.
        Record prediction_outcome from original tools, including missing/failed evidence. Only the chosen action is observed;
        alternative outcomes are untested counterfactuals. Inspect qualitative contradictions or probabilistic prediction_calibration, then publish a
        corrected model with previous_model, feedback and a discriminating next test. Do not equate one good score with calibration.
        When explanations compete, optional hypothesis_test identifies explicit prediction disagreements in qualitative mode,
        or compares information gain under declared probabilities in probabilistic mode. Original observations can contradict
        every proposed explanation; then revise the problem model or measurement, not force a winning explanation.
        Use evidence to choose the next real probe or method, not repeated vague research. No observation is not a negative result.
        Reuse preserved outcomes rather than repeat completed side effects. Ordinary direct work does not require forecasting.
    """.trimIndent()

    fun rules() = """
        All prediction records are immutable, group-scoped workspace kinds. Recall original records and evidence, then publish.
        task_environment_model:{goal_sha256,criterion_id,requirement,domain,environment,scope,mechanism,uncertainty,valid_when,
          refresh_when,confounders:[text],basis:[exact artifact/evidence/proposal/counterexample/capability_probe/experiment_result/
          prediction_outcome/prediction_calibration refs],state:[{id,value,basis,epistemic_status:"observed|assumed|unknown",
          observation:<original ref required only for observed>}],actions:[{id,mode:"act|probe|defer",description,preconditions,
          expected_transition,side_effects,reversibility,authorization}]}.
        Cite/read original observations for observed state; the host does not certify the model's interpretation. Include at least
        two distinct actions and a defer/no-action alternative. No action count is a research-stage or retry limit.
        To correct a model, add previous_model:<exact ref>,feedback:[exact prediction_outcome refs],changed_assumptions,why_change,
        next_discriminating_test. Preserve goal/criterion/domain. Feedback must concern that previous model; correction is unverified.

        action_forecast:{task_environment_model:<exact ref>,work_id,executor:<person id>,horizon,valid_until:<Unix milliseconds>,
          decision_rationale,risk_tradeoff,information_value,revalidate_before_action,utility_unit,selected_action:<action id>,
          source:{origin,tool},report_pointer:"JSON pointer, empty=root",events:[{id,meaning,unit,pointer,expected:<explicit JSON scalar>,
          utility_if_true:<decimal>,utility_if_false:<decimal>}],choices:[{action_id,reasoning,uncertainty,resources,risk,
          probabilities:{<event id>:<probability 0..1>}}]}.
        Compare ALL registered actions using the SAME events and utility scale; include risks/costs as events when relevant.
        Probabilities are individual event marginals, not mutually exclusive labels; do not sum them to infer joint risk.
        The host computes linear expected utility but does not maximize it for you or certify declared utility/probabilities.
        The default mode is probabilistic. With prediction_mode:"qualitative", omit utility_unit, utility_if_true,
        utility_if_false and choices[].probabilities. Each choice instead has expectations:{<event id>:"expected|not_expected|unknown"}.
        Include exactly all registered events for every action, including defer; use unknown where an action makes no prediction.
        expected means the registered equality is predicted true; not_expected predicts it false. These are testable claims,
        NOT calibrated certainty. All other source, event, choice rationale and work binding fields remain required.
        Numeric utility/information gain and Brier scores stay null in qualitative mode, never zero or a fabricated probability.
        The validity deadline reflects environmental freshness, not a task timeout or permission. Register before observation.
        work[] uses prediction_work:{forecast:<exact ref>}; work ID, executor, original goal and criterion must match.
        Both live and next-round planners deliver immutable forecast/action context to actual workers. Recovery preserves the
        original binding; recheck validity/preconditions before each new external action, create a new forecast/work for replanning.

        An authorized tool/harness reports {format:"galaxyssi.action-outcome.v1",forecast_sha256,model_sha256,action_id,work_id,
          environment,<observable fields>}. report_pointer can select an object or exact JSON text in Desktop stdout wrappers.
        prediction_outcome:{action_forecast:<exact ref>,interpretation,confounders,model_correction,next_action,
          checks:[{event_id,observation:<exact original receipt>}]} plus observations:[all cited receipts].
        Read originals first. Source tool/origin, run/turn/executor, time and report identities must match. Actual field equality
        defines whether the preregistered event occurred; the host computes (probability - outcome)^2, not model-written scores.
        Tool failure or missing field is unobserved, never a false event. Empty/partial checks preserve incomplete evidence.
        Later evidence uses a new immutable outcome snapshot; never count snapshots of the same forecast twice in an aggregate.
        The host verifies original report provenance, not the semantic correctness of a self-written harness or causal attribution.

        In qualitative mode, hypothesis_test instead uses {question,assumptions,prediction_basis,misspecification_check,
          hypotheses:[{id,claim}],event_ids:[one or more registered events],
          predictions:{<action id>:{<hypothesis id>:{<event id>:"expected|not_expected|unknown"}}}}.
        Do not supply priors, likelihoods or prior_outcome. The host records event IDs with opposing explicit predictions for
        each action; their count is NOT an information-gain or utility estimate. An uninformative experiment remains allowed
        but visible as such. Choose based on actual decision gaps, feasibility and resources; do not maximize a label count.
        Checks use ONE original measurement, not spliced trials. Failed/missing/stale fields and unknown expectations cannot
        confirm or contradict a hypothesis. Outcomes preserve matched, contradicted and unresolved event IDs for each claim.
        Consistency is not proof; contradictory evidence remains even when other predictions are unresolved. If all explanations
        are contradicted, retain the raw result and propose new variables, assumptions or a different discriminating test.
        Correct the task_environment_model using exact prediction_outcome feedback and publish a NEW forecast before a new
        experiment. Do not silently edit claims or convert these labels into Bayesian posterior weights.
        Use original observation fields with existing workflow observed_inputs to drive subsequent admitted work where applicable;
        the forecast report alone neither chooses nor executes the next action and does not prove a method is better.

        Optional action_forecast.hypothesis_test:{question,assumptions,likelihood_basis,misspecification_check,
          hypotheses:[{id,claim,prior:<probability>}],event_ids:[registered categorical event IDs],
          likelihoods:{<action id>:{<hypothesis id>:{<event id>:<probability>}}}}.
        Register at least two distinct hypotheses and categorical outcomes. Every event classifies the SAME report pointer with a
        distinct scalar expected value; include a scientifically meaningful other/unknown outcome where needed. Every action,
        including defer, needs a distribution over the same categories under each hypothesis. Distributions sum to one (1e-12 tolerance);
        priors/likelihoods are finite decimal probabilities in [0,1], not confidence labels or empirical calibration proof.
        Action event marginals in choices must equal the prior-weighted likelihoods; errors name inconsistent fields and values.
        Host action_information computes E[KL(posterior||prior)] in bits under these declared assumptions. Consider cost, risks,
        feasibility and utility alongside information value; the host does not maximize it for you or execute an experiment.
        Bind the selected action with existing prediction_work; it carries the immutable comparison into the real task graph.
        Outcome checks for all these event IDs must cite ONE original observation. Missing/failed/stale observations yield no posterior;
        unregistered categories and zero prior-predictive mass preserve model-misspecification states, never fabricated certainty.
        A valid observation computes posterior weights, KL information and entropy change. Individual entropy can increase;
        a high posterior is conditional on the assumed likelihoods and hypothesis space, not proof the explanation is true.
        For the next experiment use hypothesis_test.prior_outcome:<exact prediction_outcome ref>, conditional_history:<text>,
        and omit prior from every hypothesis. The host carries the exact observed posterior; question, hypotheses, original goal,
        criterion, domain and environment must match. Likelihoods must condition on the entire prior history; explain dependence,
        overlapping data and confounders in conditional_history. Never treat repeated observations as independent by default.
        A changed hypothesis space starts a new comparison with explicit priors and provenance, not renamed posterior weights.
        Use resulting evidence as a basis for innovation_opportunity, corrected environment models or revised methods. A retained
        workflow_selection_rule still needs its own controlled comparison and independent lesson; posterior confidence cannot bypass it.

        prediction_calibration:{task_environment_model:<exact ref>,outcomes:[exact prediction_outcome refs],sampling_scope,
          selection_bias,limitations,next_test}. The host reports event counts, missingness and mean Brier score for that exact model.
        Calibration accepts probabilistic outcomes only; qualitative contradictions must not be pooled as perfect probability scores.
        This is a selected-sample accuracy score, NOT a proof of calibration, independence, model improvement or optimal decisions.
        Retain errors, examine domain/selection bias and correlated outcomes; test corrected models on NEW held-out future actions.
        No prediction or simulation fulfills physical experiment acceptance, installs tools, expands authority or stops a goal.
    """.trimIndent()
}
