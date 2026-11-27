import com.galaxyssi.chat.AutoGoalTeamEngineKt;
import java.net.*;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import kotlin.Unit;
import kotlin.coroutines.*;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.future.FutureKt;
import org.json.*;

/** Opt-in host smoke test. Only a fixed, public, synthetic task is sent to a loopback model. */
class LocalTeamAcceptance {
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
    final URI endpoint;
    final String model;

    LocalTeamAcceptance(int port, String model) {
        endpoint = URI.create("http://127.0.0.1:" + port + "/v1/chat/completions");
        this.model = model;
    }

    Object ask(String system, String input, Continuation<? super String> continuation) {
        JSONObject call = new JSONObject(input);
        calls.add(call);
        JSONArray messages = new JSONArray()
            .put(new JSONObject().put("role", "system").put("content", system))
            .put(new JSONObject().put("role", "user").put("content", input));
        JSONObject body = new JSONObject().put("model", model).put("messages", messages)
            .put("temperature", 0).put("seed", 42).put("stream", false).put("max_tokens", 850)
            .put("chat_template_kwargs", new JSONObject().put("enable_thinking", false));
        body.putOpt("response_format", AutoGoalTeamEngineKt.teamAuditOutputFormat(system, endpoint.toString()));
        HttpRequest request = HttpRequest.newBuilder(endpoint).timeout(Duration.ofSeconds(110))
            .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body.toString())).build();
        var requestFuture = client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        var result = requestFuture.thenApply(response -> {
            require(response.statusCode() == 200, "Model HTTP " + response.statusCode());
            JSONObject reply = new JSONObject(response.body());
            require(ids.add(reply.getString("id")), "Model reused a completion ID");
            JSONObject choice = reply.getJSONArray("choices").getJSONObject(0);
            require("stop".equals(choice.getString("finish_reason")), "Incomplete generation");
            String content = choice.getJSONObject("message").getString("content");
            String stage = call.getString("stage");
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

    void run(boolean swapped) throws Exception {
        String answer = BuildersKt.<String>runBlocking(EmptyCoroutineContext.INSTANCE,
            (scope, cont) -> AutoGoalTeamEngineKt.runAutoGoalTeam(task(swapped), this::ask,
                event -> { System.out.println(event); return Unit.INSTANCE; }, cont));
        var roles = calls.stream().filter(c -> Set.of("role","audit").contains(c.getString("stage"))).toList();
        require(roles.size() >= 2 && roles.size() <= 10 && ids.size() == roles.size()+2, "Expected real independent calls");
        require(roles.stream().anyMatch(r -> Set.of("reviewer","dissent").contains(r.getString("kind"))), "No independent check");
        require(roles.stream().anyMatch(r -> !r.getJSONArray("reports").isEmpty()), "No handoff observed");
        JSONObject synthesis = calls.stream().filter(c -> c.getString("stage").equals("synthesis")).findFirst().orElseThrow();
        var reports = synthesis.getJSONArray("reports");
        var audits = calls.stream().filter(c -> c.getString("stage").equals("audit")).toList();
        require(audits.size() == 1 && calls.indexOf(audits.get(0)) > calls.indexOf(synthesis) &&
            !audits.get(0).getString("draft").isBlank(), "No independent final-draft review");
        require(reports.length() == roles.size()-1, "Missing contributor report at synthesis");
        var audit = audits.get(0);
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
        System.out.println("Final public answer:\n" + answer);
        System.out.println("Transport verified: " + roles.size() + " model-chosen roles, " + ids.size() + " distinct completions.");
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
        if (args.length != 2 && !(args.length == 3 && args[2].equals("--swap")))
            throw new IllegalArgumentException("Expected loopback port, local model ID, optional --swap");
        new LocalTeamAcceptance(Integer.parseInt(args[0]), args[1]).run(args.length == 3);
    }
}
