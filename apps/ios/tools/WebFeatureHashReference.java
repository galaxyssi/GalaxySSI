// JDK reference-data generator only; not an iOS or Android native test.
// Arithmetic/token order follows Android #3007 65655f0c AgentWebIntelligenceEmbedder.
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.Normalizer;
import java.util.*;
import java.util.regex.*;

class WebFeatureHashReference {
  static float[] embed(String value, int dimensions) throws Exception {
    String text = Normalizer.normalize(value, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
    List<String> features = new ArrayList<>();
    Matcher latin = Pattern.compile("[a-z0-9][a-z0-9_+.-]{1,}").matcher(text);
    while (latin.find()) features.add(latin.group());
    Matcher cjk = Pattern.compile("[\\u3400-\\u9fff]+").matcher(text);
    while (cjk.find()) {
      String group = cjk.group();
      if (group.length() == 1) features.add(group);
      else for (int i = 0; i < group.length() - 1; i++) features.add(group.substring(i, i + 2));
    }
    for (int i = 0; i <= text.length() - 3; i++) {
      String feature = text.substring(i, i + 3);
      if (feature.chars().noneMatch(c -> Character.isWhitespace(c) || Character.isSpaceChar(c))) features.add(feature);
    }
    Map<String, Integer> counts = new LinkedHashMap<>();
    for (String feature : features) counts.merge(feature, 1, Integer::sum);
    float[] vector = new float[dimensions];
    for (var entry : counts.entrySet()) {
      byte[] digest = MessageDigest.getInstance("SHA-256").digest(entry.getKey().getBytes(StandardCharsets.UTF_8));
      long raw = 0;
      for (int i = 0; i < 8; i++) raw = (raw << 8) | (digest[i] & 255L);
      int index = (int)((raw & Long.MAX_VALUE) % dimensions);
      float sign = raw < 0 ? -1f : 1f;
      vector[index] += sign * (float)(1 + Math.log(1 + entry.getValue()));
    }
    double sum = 0;
    for (float v : vector) sum += (double)v * v;
    float norm = (float)Math.sqrt(sum);
    if (!(norm > 0)) norm = 1;
    for (int i = 0; i < vector.length; i++) vector[i] /= norm;
    return vector;
  }

  public static void main(String[] args) throws Exception {
    String[] labels = {"empty", "ascii", "repeat", "compat", "cjk", "supplementary", "whitespace", "bounded"};
    String[] texts = {"", "alpha beta", "alpha alpha", "\uff21\uff29 \u212a",
      "\u4f60\u597d\u4e16\u754c", "a\ud83d\ude00b", "ab\u0085cd\u001cef", "\nab\ud83d"};
    System.out.print("[");
    for (int i = 0; i < texts.length; i++) {
      if (i > 0) System.out.print(",");
      System.out.print("{\"label\":\"" + labels[i] + "\",\"bits\":[");
      float[] vector = embed(texts[i], 192);
      boolean first = true;
      for (int n = 0; n < vector.length; n++) if (vector[n] != 0) {
        if (!first) System.out.print(",");
        first = false;
        System.out.print("[" + n + "," + Integer.toUnsignedString(Float.floatToRawIntBits(vector[n])) + "]");
      }
      System.out.print("]}");
    }
    System.out.println("]");
  }
}
