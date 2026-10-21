package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class DesktopControlCanonicalJsonTest {
    @Test fun digestMatchesDesktopPythonAcrossEscapingAndUnicode() {
        val value = JSONObject()
            .put("contract_version", "galaxyssi.desktop-control/1.6")
            .put("image_mime", "image/jpeg")
            .put("text", "</tag>\u2028\u2029\u0000\n\t\\/\"\u4e2d\u6587")
        // Python json.dumps(ensure_ascii=False, sort_keys=True, separators=(',', ':')).
        assertEquals("3d9f851b7ac913baa5dd80afd1ab6211245b17a0c0ad4e4a22bec2e841522744",
            DesktopControlReceiptProtocol.digest(value))
    }

    @Test fun nestedValuesKeepStableOrderAndTypes() {
        val value = JSONObject().put("z", JSONArray().put(JSONObject.NULL)
            .put(true).put(42L).put(JSONObject().put("b", "image/jpeg").put("a", "</tag>")))
            .put("a", "\\/")
        assertEquals("{\"a\":\"\\\\/\",\"z\":[null,true,42,{\"a\":\"</tag>\",\"b\":\"image/jpeg\"}]}",
            desktopControlCanonicalJson(value))
        assertEquals(desktopControlCanonicalJson(value), desktopControlCanonicalJson(JSONObject(value.toString())))
    }
}
