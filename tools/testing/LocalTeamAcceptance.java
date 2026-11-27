import com.galaxyssi.chat.AutoGoalTeamEngineKt;
import com.galaxyssi.chat.AutoGoalTeamCommand;
import com.galaxyssi.chat.TeamAnswerWithheld;
import com.galaxyssi.chat.TeamContrastText;
import com.galaxyssi.chat.TeamResultLabels;
import java.net.*;
import java.net.http.*;
import java.nio.file.Path;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import kotlin.Unit;
import kotlin.coroutines.*;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.future.FutureKt;
import org.json.*;

/** Opt-in host smoke test. Only a fixed, public, synthetic task is sent to a loopback model. */
class LocalTeamAcceptance {
    // No candidate name, mechanism, comparison table or expected winning idea is supplied.
    static final String CONCEPT_TURN = """
        请自动组队，为苯丙酮尿症（PKU）的体外研究提出一个候选蛋白的功能构想，并独立审核最后的答复。
        公开背景：PKU 会使血中苯丙氨酸升高。没有提供任何候选蛋白或实测数据。
        请自行提出一个不进入人体的研究用读数构想：它要报告什么，什么现象会让你放弃这个解释？
        用中文区分已知背景、设计目标和仍缺的证据。不要给序列、制备或实验步骤，不作诊疗或新颖性声明。
        """.strip();

    static String admit(String turn) {
        var command = AutoGoalTeamCommand.Companion.parse(turn);
        require(command instanceof AutoGoalTeamCommand.Start, "The ordinary Chinese turn did not request a team");
        String objective = ((AutoGoalTeamCommand.Start)command).getObjective();
        require(turn.equals(objective), "Chat admission changed the objective");
        return objective;
    }

    // A fresh chat, not a replay of the review and not a list of candidate answers.
    static final String FALSIFIABLE_TURN = """
        请自动组队，为苯丙酮尿症（PKU）的体外研究构想一种假想的报告蛋白，并独立审核最终答复。
        公开背景只有一条：PKU 可使血中苯丙氨酸升高。不存在候选名单或实测结果。
        用四句中文给出：蛋白想报告什么；假设成立时应看到的变化；同样前提下哪种观察与该预测不能同时成立；还缺什么证据。
        不把“尚未测量”当成反证，不用已知蛋白冒充新设计。只谈功能，不给序列、实验步骤或诊疗结论。
        """.strip();

    static String challenge(String published) {
        return admit("""
            请自动组队复查上一轮的 PKU 体外报告蛋白构想，并独立审核最终答复。
            上轮公开答复只是待质疑的材料。用功能定义假想的报告蛋白，不给它套用未经核实的已知蛋白名称。
            用中文分别给出：它要报告的量、假设成立时应观察到的变化、真正与这一预测矛盾的观察，以及尚缺的证据。
            逐句核对原答复的反证条件：它否定的是原假设，还是恰好符合预测？请给出修正后的构想。
            各角色用一两句简报发现；最终答复用四至六句，保留上述全部要点。
            只谈可检验的功能，不给序列、制备或实验步骤，不作新颖性、诊断或疗效声明。
            上轮已公开答复：
            """ + published);
    }
    static String task(boolean swapped) {
        return "Evaluate fictional Phe-Buffer, a hypothetical protein function for PKU. "
        + "The proposed function is to reduce excess phenylalanine (Phe) while sparing low Phe. "
        + "Compare two toy response curves " + (swapped ? "B=x/(1+x) and A=x*x/(1+x*x)" : "A=x/(1+x) and B=x*x/(1+x*x)") + " at x=0.25,1,4. "
        + "The invented gates are response <0.10 at 0.25 and >0.85 at 4. "
        + "Independently audit the claim that matching the midpoint proves clinical benefit. "
        + "Give the six values, say which curve meets both toy gates, and distinguish a desired property "
        + "from something measured in a molecule. No real patients, sequences, or protocols. "
        + "Source: independently calculated mathematical reference, not measurements:\n" + table(swapped);
    }
    final HttpClient client = HttpClient.newBuilder().proxy(ProxySelector.of(null))
        .connectTimeout(Duration.ofSeconds(5)).followRedirects(HttpClient.Redirect.NEVER).build();
    final Set<String> ids = ConcurrentHashMap.newKeySet();
    final List<JSONObject> calls = new CopyOnWriteArrayList<>();
    final Map<String,String> findings = new ConcurrentHashMap<>();
    volatile String draft;
    volatile String rewrite, firstReview, finalCheck;
    final URI endpoint;
    final String model;
    final boolean schemaPlan;

    LocalTeamAcceptance(int port, String model, boolean schemaPlan) {
        endpoint = URI.create("http://127.0.0.1:" + port + "/v1/chat/completions");
        this.model = model;
        this.schemaPlan = schemaPlan;
    }

    Object ask(String system, String input, Continuation<? super String> continuation) {
        JSONObject call = new JSONObject(input);
        calls.add(call);
        var planWire = AutoGoalTeamEngineKt.teamPlanWire(system, endpoint.toString(), schemaPlan ? "llama.cpp-json-schema" : "openai");
        JSONArray messages = new JSONArray()
            .put(new JSONObject().put("role", "system").put("content", planWire == null ? system : planWire.getSystem()))
            .put(new JSONObject().put("role", "user").put("content", input));
        JSONObject body = new JSONObject().put("model", model).put("messages", messages)
            .put("temperature", 0).put("seed", 42).put("stream", false).put("max_tokens", 850)
            .put("chat_template_kwargs", new JSONObject().put("enable_thinking", false));
        body.putOpt("response_format", planWire == null ? AutoGoalTeamEngineKt.teamAuditOutputFormat(system, endpoint.toString()) : planWire.getRequestFormat());
        HttpRequest request = HttpRequest.newBuilder(endpoint).timeout(Duration.ofSeconds(110))
            .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body.toString())).build();
        var requestFuture = client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        var result = requestFuture.thenApply(response -> {
            require(response.statusCode() == 200, "Model HTTP " + response.statusCode());
            JSONObject reply = new JSONObject(response.body());
            require(ids.add(reply.getString("id")), "Model reused a completion ID");
            JSONObject choice = reply.getJSONArray("choices").getJSONObject(0);
            String finish = choice.optString("finish_reason");
            JSONObject usage = reply.optJSONObject("usage");
            require("stop".equals(finish), "Incomplete " + call.getString("stage") +
                " generation (length limit=" + "length".equals(finish) + ", completion tokens=" +
                (usage == null ? -1 : usage.optInt("completion_tokens", -1)) + ")");
            JSONObject message = choice.getJSONObject("message");
            require(!message.has("tool_calls") && !message.has("function_call"), "Unexpected tool request");
            String raw = message.getString("content");
            String content = planWire == null ? raw : planWire.decode(raw);
            String stage = call.getString("stage");
            if (stage.equals("role")) findings.put(call.getString("id"), content);
            if (stage.equals("synthesis")) draft = content;
            if (stage.equals("audit")) firstReview = content;
            if (stage.equals("rewrite")) rewrite = content;
            if (stage.equals("recheck")) finalCheck = content;
            // Log the shape, never thoughts or the raw response to a malformed call.
            String shape = content.lines().limit(14).map(line -> {
                int pipe = line.indexOf('|');
                return pipe > 0 && pipe < 12 && line.substring(0, pipe).matches("[A-Z]+")
                    ? line.substring(0, pipe) : line.trim().equals("END") ? "END" : "text";
            }).reduce((a,b) -> a + "," + b).orElse("empty");
            System.out.println(stage + " " + call.optString("id") + " " + shape);
            if (stage.equals("role") && content.trim().startsWith("{")) {
                var tokener = new JSONTokener(content);
                JSONObject obj = (JSONObject) tokener.nextValue();
                System.out.printf("  %s: keys=%s, trailing=%s, parents=%d%n", call.getString("id"),
                    obj.keySet().stream().filter(k -> k.matches("[a-zA-Z_]{1,20}")).toList(),
                    tokener.nextClean() != 0, call.getJSONArray("reports").length());
            }
            return content;
        });
        result.whenComplete((v,e) -> { if (result.isCancelled()) requestFuture.cancel(true); });
        return FutureKt.await(result, continuation);
    }

    static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }

    static String unwrap(String response) {
        String raw = Objects.requireNonNull(response).strip().replace("\r\n", "\n");
        if (raw.startsWith("```json\n") && raw.endsWith("\n```")) raw = raw.substring(8, raw.length()-4).strip();
        return raw;
    }

    // The host compares public fields from separate completions, not inferred role labels.
    static String publicField(String response, String field) {
        String raw = unwrap(response);
        if (raw.startsWith("{")) return new JSONObject(raw).getString(field).strip();
        if (field.equals("finding") && raw.startsWith("FINDING|") && raw.endsWith("\nEND"))
            return raw.lines().findFirst().orElseThrow().substring(8).strip();
        if (field.equals("answer") && raw.endsWith("\nEND")) return raw.substring(0, raw.length()-4).strip();
        throw new IllegalStateException("Missing complete public " + field);
    }

    record ContrastWords(String format, String higher, String lower) {
        static ContrastWords load(String objective) throws Exception {
            boolean chinese = objective.codePoints().anyMatch(c -> Character.UnicodeScript.of(c) == Character.UnicodeScript.HAN);
            Path path = Path.of("apps/android/app/src/main/res", chinese ? "values-zh" : "values", "team_prediction_contrast.xml");
            var factory = DocumentBuilderFactory.newInstance();
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
            var strings = factory.newDocumentBuilder().parse(path.toFile()).getDocumentElement().getElementsByTagName("string");
            Map<String,String> words = new HashMap<>();
            for (int i = 0; i < strings.getLength(); i++) {
                var item = (org.w3c.dom.Element) strings.item(i);
                var key = item.getAttribute("name");
                require(words.putIfAbsent(key, item.getTextContent().replace("\\n", "\n")) == null, "Duplicate resource: " + key);
            }
            return new ContrastWords(word(words, "team_contrast_format"), word(words, "team_contrast_higher"),
                word(words, "team_contrast_lower"));
        }

        static String word(Map<String,String> words, String key) {
            String value = words.get(key);
            require(value != null && !value.isBlank(), "Missing contrast resource: " + key);
            return value;
        }

        TeamResultLabels labels() { return new TeamResultLabels(new TeamContrastText(format, higher, lower)); }

        String direction(String value) {
            return switch (value) {
                case "higher" -> higher;
                case "lower" -> lower;
                default -> throw new IllegalStateException("Invalid contrast direction");
            };
        }
    }

    record WriterWitness(String text, JSONObject claim) {
        boolean structured() { return claim != null; }
    }

    static String writerText(JSONObject obj, String key) {
        String text = obj.getString(key).replaceAll("^[\\p{javaWhitespace}\\p{Z}]+|[\\p{javaWhitespace}\\p{Z}]+$", "");
        require(!text.isEmpty(), "Blank writer field: " + key);
        return text;
    }

    static WriterWitness writerWitness(String response, ContrastWords words) {
        String raw = unwrap(response);
        if (!raw.startsWith("{")) return new WriterWitness(publicField(response, "answer"), null);
        var reader = new JSONTokener(raw);
        JSONObject obj = new JSONObject(reader);
        require(reader.nextClean() == 0, "Trailing writer reply");
        if (obj.keySet().equals(Set.of("answer"))) return new WriterWitness(writerText(obj, "answer"), null);
        require(obj.keySet().equals(Set.of("purpose", "input", "input_direction", "readout", "expected_direction",
            "alternative", "gap")), "Unexpected writer fields");
        String expected = obj.getString("expected_direction");
        String text = String.format(Locale.ROOT, words.format(), writerText(obj, "purpose"), writerText(obj, "input"),
            words.direction(obj.getString("input_direction")), writerText(obj, "readout"), words.direction(expected),
            words.direction("higher".equals(expected) ? "lower" : "higher"), writerText(obj, "alternative"), writerText(obj, "gap"));
        return new WriterWitness(text, obj);
    }

    static boolean publishedBody(String publication, String body) {
        return !body.isBlank() && (publication.equals(body) || publication.startsWith(body + "\n\n"));
    }

    static void checkWriterRubric() throws Exception {
        var claim = new JSONObject().put("purpose", "P").put("input", "I").put("readout", "R")
            .put("alternative", "A").put("gap", "G").put("input_direction", "higher").put("expected_direction", "lower");
        var reordered = new ContrastWords("%8$s:%7$s\n%2$s:%3$s:%1$s:%4$s:%5$s:%6$s:%2$s", "H", "L");
        require(writerWitness(claim.toString(), reordered).text().equals("G:A\nI:H:P:R:L:H:I"), "Incorrect positional witness");
        claim.put("input_direction", "lower").put("expected_direction", "higher");
        require(writerWitness(claim.toString(), reordered).text().equals("G:A\nI:L:P:R:H:L:I"), "Incorrect opposite direction");
        for (String fixture : List.of(task(false), FALSIFIABLE_TURN)) {
            var words = ContrastWords.load(fixture);
            var witness = writerWitness(claim.toString(), words);
            require(witness.structured() && witness.text().contains("\n") && !witness.text().contains("\\n"),
                "Localized writer witness did not expand line breaks");
            var free = writerWitness(new JSONObject().put("answer", witness.text()).toString(), words);
            require(!free.structured() && free.text().equals(witness.text()), "Prose was mistaken for a structured witness");
        }
    }

    static String reference(boolean swapped) {
        var table = new StringJoiner("; ");
        for (double x : new double[]{0.25,1,4}) {
            double a=x/(1+x), b=x*x/(1+x*x);
            table.add(String.format(Locale.ROOT,"x=%s: A=%.3f, B=%.3f",x,swapped?b:a,swapped?a:b));
        }
        return table.toString();
    }

    static String table(boolean swapped) {
        StringBuilder table = new StringBuilder("| input | gate | A | B |\n|---|---|---|---|");
        for (double x : new double[]{0.25,1,4}) {
            double a=x/(1+x), b=x*x/(1+x*x);
            table.append(String.format(Locale.ROOT,"\n| %s | %s | %.3f | %.3f |", x,
                x == 0.25 ? "<0.10" : x == 4 ? ">0.85" : "-", swapped?b:a, swapped?a:b));
        }
        return table.toString();
    }

    String run(boolean swapped, String conceptTurn) throws Exception {
        boolean concept = conceptTurn != null;
        String objective = concept ? conceptTurn : task(swapped);
        var words = ContrastWords.load(objective);
        var labels = words.labels();
        String answer;
        boolean withheld = false;
        try {
            answer = BuildersKt.<String>runBlocking(EmptyCoroutineContext.INSTANCE,
                (scope, cont) -> AutoGoalTeamEngineKt.runAutoGoalTeam(objective, labels, this::ask,
                    event -> { System.out.println(event); return Unit.INSTANCE; }, cont));
        } catch (TeamAnswerWithheld e) {
            if (!concept) throw e;
            withheld = true;
            answer = e.getReservation() + e.getPublicObjections();
        }
        var roles = calls.stream().filter(c -> Set.of("role","audit").contains(c.getString("stage"))).toList();
        var rewrites = calls.stream().filter(c -> c.getString("stage").equals("rewrite")).toList();
        var rechecks = calls.stream().filter(c -> c.getString("stage").equals("recheck")).toList();
        require(rewrites.size() <= 1 && rechecks.size() <= rewrites.size() &&
            roles.size() >= 2 && roles.size() <= 10 && ids.size() == calls.size() && ids.size() <= 12 &&
            ids.size() == roles.size()+2+rewrites.size()+rechecks.size(), "Unexpected role or call accounting");
        require(roles.stream().anyMatch(r -> Set.of("reviewer","dissent").contains(r.getString("kind"))), "No independent check");
        if (!concept) require(roles.stream().anyMatch(r -> !r.getJSONArray("reports").isEmpty()), "No assigned report handoff");
        JSONObject synthesis = calls.stream().filter(c -> c.getString("stage").equals("synthesis")).findFirst().orElseThrow();
        var reports = synthesis.getJSONArray("reports");
        var audits = calls.stream().filter(c -> c.getString("stage").equals("audit")).toList();
        require(audits.size() == 1 && calls.indexOf(audits.get(0)) > calls.indexOf(synthesis) &&
            !audits.get(0).getString("draft").isBlank(), "No independent final-draft review");
        require(reports.length() == roles.size()-1, "Missing contributor report at synthesis");
        var audit = audits.get(0);
        var initialWitness = writerWitness(draft, words);
        boolean structuredWitness = initialWitness.structured();
        require(audit.getString("draft").equals(initialWitness.text()), "Final reviewer received a different draft");
        if (!rewrites.isEmpty()) {
            var edit = rewrites.get(0);
            if (initialWitness.structured()) require(initialWitness.claim().similar(edit.optJSONObject("original_claim")),
                "Writer handback lost its original structured claim");
            require(calls.indexOf(edit) > calls.indexOf(audit) && edit.getString("draft").equals(audit.getString("draft")) &&
                edit.getString("brief").equals(synthesis.getString("brief")) &&
                edit.getJSONArray("reports").similar(reports) && Set.of("revise", "request_changes").contains(publicField(firstReview,"verdict")) &&
                publicField(firstReview,"objection").equals(edit.getString("objection")), "Writer handback lost its source");
            if (rechecks.isEmpty()) require(withheld, "Rewrite published without a recheck");
            else {
                var check = rechecks.get(0);
                var replacement = writerWitness(rewrite, words);
                require(!initialWitness.structured() || replacement.structured(), "Structured rewrite lost its claim fields");
                require(calls.indexOf(check) > calls.indexOf(edit) && check.getString("id").equals(audit.getString("id")) &&
                    !replacement.text().replaceAll("(?U)\\s+", " ").strip().equals(initialWitness.text().replaceAll("(?U)\\s+", " ").strip()) &&
                    check.getString("draft").equals(replacement.text()) &&
                    check.getString("rejected_draft").equals(edit.getString("draft")) &&
                    check.getString("objection").equals(edit.getString("objection")) &&
                    check.getJSONArray("reports").similar(audit.getJSONArray("reports")), "Recheck did not receive the actual handback");
                structuredWitness |= replacement.structured();
                if (!withheld) require(publicField(finalCheck,"verdict").equals("accept") && publishedBody(answer, replacement.text()),
                    "Return is not the independently approved replacement");
            }
        } else if (!withheld && !audit.has("verified_table")) {
            String approved = switch (publicField(firstReview, "verdict")) {
                case "accept" -> initialWitness.text();
                case "revise" -> {
                    require(!initialWitness.structured(), "Structured revision bypassed the writer and recheck");
                    yield publicField(firstReview, "answer");
                }
                default -> throw new IllegalStateException("Publication without final approval");
            };
            require(publishedBody(answer, approved), "Return is not the independently approved draft");
        }
        require(findings.size() == reports.length(), "Contributor completion count does not match synthesis");
        for (int i=0; i<reports.length(); i++) {
            var report = reports.getJSONObject(i);
            require(report.getString("finding").equals(publicField(findings.get(report.getString("id")), "finding")),
                "Synthesis did not receive the original contributor finding");
        }
        var parents = audit.getJSONArray("reports");
        Set<String> assigned = new HashSet<>();
        for (int i=0; i<parents.length(); i++) assigned.add(parents.getJSONObject(i).getString("id"));
        Map<String,String> expectedObjections = new LinkedHashMap<>();
        for (int i=0; i<reports.length(); i++) {
            JSONObject report = reports.getJSONObject(i);
            if (!report.isNull("dissent")) {
                String id = report.getString("id"), dissent = report.getString("dissent");
                require(answer.contains(dissent), "Dropped reservation");
                if (!assigned.contains(id)) expectedObjections.put(id, dissent);
            }
        }
        var additional = audit.optJSONArray("additional_objections");
        int count = additional == null ? 0 : additional.length();
        require(count == expectedObjections.size(), "Incorrect number of non-parent objections in audit");
        for (int i=0; i<count; i++) {
            var entry = additional.getJSONObject(i);
            require(entry.keySet().equals(Set.of("id","dissent")) &&
                entry.getString("dissent").equals(expectedObjections.remove(entry.getString("id"))),
                "Audit did not receive exactly the originating role's public objection");
        }
        require(expectedObjections.isEmpty(), "Missing non-parent objection");
        System.out.println((withheld ? "Review withheld the draft:\n" : "Final public answer:\n") + answer);
        System.out.println("Transport verified: " + roles.size() + " model-chosen roles, " + ids.size() + " distinct completions.");
        System.out.println("Structured writer witness verified: " + structuredWitness);
        if (concept) {
            require(calls.stream().allMatch(c -> objective.equals(c.getString("objective")) && !c.has("verified_table")),
                "The open-ended fixture changed or received a precomputed answer");
            require(!withheld, "Collaboration verified, but no concept was released");
            System.out.println("Inspect the proposed readout, its falsifier and missing evidence. No molecule or clinical claim is validated.");
            return answer;
        }
        System.out.println("Numerical reference (fictional model only): " + reference(swapped));
        // A returned paragraph alone is not evidence of scientific or even arithmetic correctness.
        String finalBody = answer.split("\n\n(?:Reviewer correction:|Reported disagreements:)", 2)[0];
        var reported = java.util.regex.Pattern.compile("(?<![0-9.])(?:0?\\.[0-9]+)(?![0-9])")
            .matcher(finalBody).results().map(m -> Double.parseDouble(m.group())).toList();
        for (double expected : new double[]{0.2,1.0/17,0.5,0.8,16.0/17}) {
            require(reported.stream().anyMatch(n -> Math.abs(n-expected) <= 0.0011),
                "Public answer omitted a reference value: " + expected);
        }
        require(finalBody.contains(table(swapped)), "Source labels or values changed at publication");
        screenVerdict(finalBody, swapped);
        System.out.println("Basic numeric and contradiction checks passed. Interpretation still requires review.");
        return answer;
    }

    static void screenVerdict(String answer, boolean swapped) {
        String lower = answer.toLowerCase(Locale.ROOT);
        String winner=swapped?"a":"b", loser=swapped?"b":"a";
        String success = "\\s+(?:is the (?:only )?(?:one|curve) (?:that|which) |)(?:meets?|passes?|satisfies|satisfy)\\b[^.!?\\n]{0,45}\\bboth\\b";
        require(!java.util.regex.Pattern.compile("\\b(?:curve\\s+)?"+loser+success).matcher(lower).find(),
            "Contradiction: "+loser+" does not meet the toy gates");
        require(lower.lines().anyMatch(("pass all gates: "+winner)::equals) ||
            java.util.regex.Pattern.compile("\\b(?:curve\\s+)?"+winner+success).matcher(lower).find(),
            "No explicit supported verdict; manual review needed");
        require(lower.contains("clinical") && java.util.regex.Pattern.compile(
            "\\b(?:not|no|cannot|unverified|unproven|unknown|unsupported|insufficient)\\b").matcher(lower).find(),
            "No explicit limitation on clinical inference; manual review needed");
    }

    public static void main(String[] args) throws Exception {
        if (Arrays.equals(args, new String[]{"--check-rubric"})) {
            checkWriterRubric();
            admit(CONCEPT_TURN);
            admit(FALSIFIABLE_TURN);
            require(challenge("Public synthetic draft.").endsWith("Public synthetic draft."), "Lost follow-up evidence");
            String good = "B meets both toy gates. No clinical evidence.";
            screenVerdict(good, false);
            screenVerdict("A meets both toy gates. No clinical evidence.", true);
            for (String bad : List.of(good + " Curve A meets both toy gates.", "B meets both toy gates.", "No clinical evidence.")) {
                try { screenVerdict(bad, false); } catch (IllegalStateException expected) { continue; }
                throw new AssertionError("Rubric missed a known invalid verdict");
            }
            System.out.println("Rubric regressions passed (no model called).");
            return;
        }
        if (args.length < 2) throw new IllegalArgumentException("Expected loopback port and local model ID");
        var extra = List.of(args).subList(2, args.length);
        var opts = Set.copyOf(extra);
        require(opts.size() == extra.size() && Set.of("--swap", "--concept", "--schema-plan", "--review-concept", "--falsifiable-concept").containsAll(opts) &&
            (!opts.contains("--falsifiable-concept") || Collections.disjoint(opts, Set.of("--swap","--concept","--review-concept"))) &&
            !(opts.contains("--swap") && opts.contains("--concept")) && (!opts.contains("--review-concept") || opts.contains("--concept")),
            "Invalid fixture options");
        int port = Integer.parseInt(args[0]);
        var initial = new LocalTeamAcceptance(port, args[1], opts.contains("--schema-plan"));
        String published = initial.run(opts.contains("--swap"), opts.contains("--falsifiable-concept") ? admit(FALSIFIABLE_TURN) :
            opts.contains("--concept") ? admit(CONCEPT_TURN) : null);
        if (opts.contains("--review-concept")) {
            System.out.println("Independent follow-up on the previous public answer:");
            var review = new LocalTeamAcceptance(port, args[1], opts.contains("--schema-plan"));
            review.run(false, challenge(published));
            require(Collections.disjoint(initial.ids, review.ids), "Repeated completion across independent turns");
        }
    }
}
