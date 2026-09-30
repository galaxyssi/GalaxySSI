package com.galaxyssi.chat;

import android.app.Activity;
import android.os.Bundle;
import android.text.InputType;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Runs separately from instrumentation without relying on the target APK's Kotlin runtime. */
public class PhoneUiFixtureActivity extends Activity {
    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        TextView status = new TextView(this);
        status.setText("Fixture idle");
        status.setTextSize(20f);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(20, 20, 20, 20);
        content.addView(status);
        Button button = new Button(this);
        button.setText("Fixture click");
        button.setOnClickListener(view -> status.setText("Fixture clicked"));
        button.setOnLongClickListener(view -> { status.setText("Fixture long clicked"); return true; });
        boolean opaque = getIntent().getBooleanExtra("opaque_page", false);
        if (!opaque) content.addView(button);
        EditText input = new EditText(this);
        input.setHint("Fixture input");
        input.setContentDescription("Fixture input");
        if (!opaque) content.addView(input);
        EditText password = new EditText(this);
        password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        password.setContentDescription("Fixture private field");
        password.setText("test-secret-never-export");
        if (!getIntent().getBooleanExtra("page_capture", false)) content.addView(password);
        for (int index = 1; index <= 80; index++) {
            TextView row = new TextView(this);
            row.setText("Fixture row " + index);
            row.setTextSize(18f);
            row.setPadding(0, 16, 0, 16);
            content.addView(row);
        }
        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        if (opaque) scroll.setImportantForAccessibility(android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        setContentView(scroll);
    }
}
