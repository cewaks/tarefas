#!/bin/bash
# Cria o widget nativo, o atalho do ícone e o botão "Feito" dentro do projeto gerado pelo Capacitor
set -e
J=android/app/src/main/java/com/tarefas/casa
R=android/app/src/main/res
mkdir -p $J $R/layout $R/xml $R/drawable $R/values

cat > $J/MainActivity.java <<'EOF'
package com.tarefas.casa;

import android.content.Intent;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    registerPlugin(WidgetBridgePlugin.class);
    super.onCreate(savedInstanceState);
    handle(getIntent());
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    handle(intent);
  }

  private void handle(Intent i) {
    if (i == null) return;
    if (i.hasExtra("task_id")) {
      WidgetBridgePlugin.setPending(this, i.getStringExtra("task_id"));
      i.removeExtra("task_id");
    } else if (i.hasExtra("quick")) {
      WidgetBridgePlugin.setPending(this, "__quick");
      i.removeExtra("quick");
    }
  }
}
EOF

cat > $J/WidgetBridgePlugin.java <<'EOF'
package com.tarefas.casa;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import org.json.JSONArray;
import org.json.JSONObject;

@CapacitorPlugin(name = "WidgetBridge")
public class WidgetBridgePlugin extends Plugin {
  static final String PREFS = "tarefas_widget";

  static void setPending(Context c, String id) {
    c.getSharedPreferences(PREFS, 0).edit().putString("pending", id).apply();
  }

  static void markDone(Context c, String id) {
    SharedPreferences sp = c.getSharedPreferences(PREFS, 0);
    try {
      JSONObject o = new JSONObject(sp.getString("data", "{}"));
      JSONArray a = o.optJSONArray("items");
      JSONArray n = new JSONArray();
      if (a != null) {
        for (int k = 0; k < a.length(); k++) {
          JSONObject it = a.getJSONObject(k);
          if (!id.equals(it.optString("id"))) n.put(it);
        }
      }
      o.put("items", n);
      JSONArray d = new JSONArray(sp.getString("dones", "[]"));
      d.put(id);
      sp.edit().putString("data", o.toString()).putString("dones", d.toString()).apply();
    } catch (Exception e) {}
    refresh(c);
  }

  @PluginMethod
  public void update(PluginCall call) {
    String json = call.getString("json", "{}");
    Context c = getContext();
    c.getSharedPreferences(PREFS, 0).edit().putString("data", json).apply();
    refresh(c);
    call.resolve();
  }

  @PluginMethod
  public void getPending(PluginCall call) {
    SharedPreferences sp = getContext().getSharedPreferences(PREFS, 0);
    String id = sp.getString("pending", "");
    sp.edit().remove("pending").apply();
    JSObject o = new JSObject();
    o.put("id", id);
    call.resolve(o);
  }

  @PluginMethod
  public void getDone(PluginCall call) {
    SharedPreferences sp = getContext().getSharedPreferences(PREFS, 0);
    String s = sp.getString("dones", "[]");
    sp.edit().remove("dones").apply();
    JSObject o = new JSObject();
    try {
      o.put("ids", new JSArray(s));
    } catch (Exception e) {
      o.put("ids", new JSArray());
    }
    call.resolve(o);
  }

  static void refresh(Context c) {
    AppWidgetManager m = AppWidgetManager.getInstance(c);
    int[] ids = m.getAppWidgetIds(new ComponentName(c, TarefasWidget.class));
    if (ids.length == 0) return;
    Intent i = new Intent(c, TarefasWidget.class);
    i.setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE);
    i.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids);
    c.sendBroadcast(i);
  }
}
EOF

cat > $J/WidgetClickActivity.java <<'EOF'
package com.tarefas.casa;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

public class WidgetClickActivity extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    Intent i = getIntent();
    String done = i.getStringExtra("done_id");
    if (done != null && !done.isEmpty()) {
      WidgetBridgePlugin.markDone(this, done);
    } else {
      Intent m = new Intent(this, MainActivity.class);
      m.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
      if (i.hasExtra("task_id")) m.putExtra("task_id", i.getStringExtra("task_id"));
      startActivity(m);
    }
    finish();
    overridePendingTransition(0, 0);
  }
}
EOF

cat > $J/TarefasWidget.java <<'EOF'
package com.tarefas.casa;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.widget.RemoteViews;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import org.json.JSONObject;

public class TarefasWidget extends AppWidgetProvider {
  @Override
  public void onUpdate(Context c, AppWidgetManager m, int[] ids) {
    for (int id : ids) upd(c, m, id);
  }

  static void upd(Context c, AppWidgetManager m, int id) {
    RemoteViews v = new RemoteViews(c.getPackageName(), R.layout.widget);
    Intent svc = new Intent(c, WidgetService.class);
    svc.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id);
    svc.setData(Uri.parse(svc.toUri(Intent.URI_INTENT_SCHEME)));
    v.setRemoteAdapter(R.id.wlist, svc);
    v.setEmptyView(R.id.wlist, R.id.wempty);

    String head = "Tarefas";
    try {
      JSONObject o = new JSONObject(c.getSharedPreferences("tarefas_widget", 0).getString("data", "{}"));
      head = o.optString("head", "Tarefas");
      String day = o.optString("day", "");
      String today = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
      if (!day.isEmpty() && !day.equals(today)) head = "Tarefas · abra o app para atualizar";
    } catch (Exception e) {}
    v.setTextViewText(R.id.whead, head);

    Intent open = new Intent(c, MainActivity.class);
    open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    PendingIntent po = PendingIntent.getActivity(c, 0, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    v.setOnClickPendingIntent(R.id.whead, po);
    v.setOnClickPendingIntent(R.id.wempty, po);

    Intent quick = new Intent(c, MainActivity.class);
    quick.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    quick.putExtra("quick", "1");
    v.setOnClickPendingIntent(R.id.wadd, PendingIntent.getActivity(c, 2, quick, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

    Intent tpl = new Intent(c, WidgetClickActivity.class);
    v.setPendingIntentTemplate(R.id.wlist, PendingIntent.getActivity(c, 1, tpl, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE));

    m.updateAppWidget(id, v);
    m.notifyAppWidgetViewDataChanged(id, R.id.wlist);
  }
}
EOF

cat > $J/WidgetService.java <<'EOF'
package com.tarefas.casa;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.util.TypedValue;
import android.view.View;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;
import org.json.JSONArray;
import org.json.JSONObject;

public class WidgetService extends RemoteViewsService {
  @Override
  public RemoteViewsFactory onGetViewFactory(Intent intent) {
    return new Factory(getApplicationContext());
  }

  static class Factory implements RemoteViewsService.RemoteViewsFactory {
    private final Context c;
    private JSONArray items = new JSONArray();

    Factory(Context c) { this.c = c; }

    @Override public void onCreate() {}
    @Override public void onDestroy() {}

    @Override
    public void onDataSetChanged() {
      try {
        JSONObject o = new JSONObject(c.getSharedPreferences("tarefas_widget", 0).getString("data", "{}"));
        JSONArray a = o.optJSONArray("items");
        items = a == null ? new JSONArray() : a;
      } catch (Exception e) {
        items = new JSONArray();
      }
    }

    @Override public int getCount() { return items.length(); }

    @Override
    public RemoteViews getViewAt(int p) {
      RemoteViews v = new RemoteViews(c.getPackageName(), R.layout.widget_item);
      try {
        JSONObject o = items.getJSONObject(p);
        String id = o.optString("id");
        v.setTextViewText(R.id.wt, o.optString("t"));
        if (o.optInt("h", 0) == 1) {
          v.setTextColor(R.id.wt, Color.parseColor("#2f6f5e"));
          v.setTextViewTextSize(R.id.wt, TypedValue.COMPLEX_UNIT_SP, 12);
          v.setViewVisibility(R.id.ws, View.GONE);
          v.setViewVisibility(R.id.wdone, View.GONE);
          v.setInt(R.id.wbar, "setBackgroundColor", Color.TRANSPARENT);
          v.setOnClickFillInIntent(R.id.wtxt, new Intent());
          return v;
        }
        String sub = o.optString("s");
        v.setTextColor(R.id.wt, Color.parseColor("#1d1d1b"));
        v.setTextViewTextSize(R.id.wt, TypedValue.COMPLEX_UNIT_SP, 14);
        v.setTextViewText(R.id.ws, sub);
        v.setViewVisibility(R.id.ws, sub.isEmpty() ? View.GONE : View.VISIBLE);
        int col = Color.parseColor(o.optString("c", "#2f6f5e"));
        v.setInt(R.id.wbar, "setBackgroundColor", col);
        Intent open = new Intent();
        open.putExtra("task_id", id);
        v.setOnClickFillInIntent(R.id.wtxt, open);
        if (o.optInt("nd", 0) == 1) {
          v.setViewVisibility(R.id.wdone, View.GONE);
        } else {
          v.setViewVisibility(R.id.wdone, View.VISIBLE);
          Intent done = new Intent();
          done.putExtra("done_id", id);
          v.setOnClickFillInIntent(R.id.wdone, done);
        }
      } catch (Exception e) {}
      return v;
    }

    @Override public RemoteViews getLoadingView() { return null; }
    @Override public int getViewTypeCount() { return 1; }
    @Override public long getItemId(int p) { return p; }
    @Override public boolean hasStableIds() { return false; }
  }
}
EOF

cat > $R/layout/widget.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="@drawable/widget_bg"
    android:padding="10dp">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:paddingBottom="6dp">
        <TextView
            android:id="@+id/whead"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Tarefas"
            android:textColor="#1d1d1b"
            android:textSize="16sp"
            android:textStyle="bold" />
        <TextView
            android:id="@+id/wadd"
            android:layout_width="34dp"
            android:layout_height="34dp"
            android:gravity="center"
            android:text="+"
            android:textColor="#ffffff"
            android:textSize="22sp"
            android:background="@drawable/widget_add" />
    </LinearLayout>
    <ListView
        android:id="@+id/wlist"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:divider="@null"
        android:dividerHeight="0dp" />
    <TextView
        android:id="@+id/wempty"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:gravity="center"
        android:text="Nada para hoje 🎉"
        android:textColor="#77756e"
        android:textSize="14sp" />
</LinearLayout>
EOF

cat > $R/layout/widget_item.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/wroot"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:paddingTop="3dp"
    android:paddingBottom="3dp">
    <LinearLayout
        android:id="@+id/wtxt"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:orientation="horizontal"
        android:gravity="center_vertical">
        <TextView
            android:id="@+id/wbar"
            android:layout_width="4dp"
            android:layout_height="32dp"
            android:layout_marginEnd="8dp" />
        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:orientation="vertical">
            <TextView
                android:id="@+id/wt"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="#1d1d1b"
                android:textSize="14sp"
                android:maxLines="1"
                android:ellipsize="end" />
            <TextView
                android:id="@+id/ws"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="#77756e"
                android:textSize="12sp"
                android:maxLines="1"
                android:ellipsize="end" />
        </LinearLayout>
    </LinearLayout>
    <TextView
        android:id="@+id/wdone"
        android:layout_width="40dp"
        android:layout_height="40dp"
        android:gravity="center"
        android:text="✓"
        android:textColor="#2f6f5e"
        android:textSize="20sp"
        android:textStyle="bold" />
</LinearLayout>
EOF

cat > $R/drawable/widget_bg.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#F6F5F1" />
    <corners android:radius="20dp" />
</shape>
EOF

cat > $R/drawable/widget_add.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#2f6f5e" />
</shape>
EOF

cat > $R/xml/widget_info.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"
    android:minHeight="180dp"
    android:minResizeWidth="180dp"
    android:minResizeHeight="110dp"
    android:resizeMode="horizontal|vertical"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/widget"
    android:widgetCategory="home_screen"
    android:description="@string/widget_desc" />
EOF

cat > $R/xml/shortcuts.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
    <shortcut
        android:shortcutId="add"
        android:enabled="true"
        android:shortcutShortLabel="@string/sc_add"
        android:shortcutLongLabel="@string/sc_add_long">
        <intent
            android:action="android.intent.action.VIEW"
            android:targetPackage="com.tarefas.casa"
            android:targetClass="com.tarefas.casa.MainActivity">
            <extra android:name="quick" android:value="1" />
        </intent>
    </shortcut>
</shortcuts>
EOF

cat > $R/values/widget_strings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="widget_desc">Suas tarefas de hoje</string>
    <string name="sc_add">Anotar</string>
    <string name="sc_add_long">Anotar nova tarefa</string>
</resources>
EOF

M=android/app/src/main/AndroidManifest.xml
# widget, serviço e atividade de clique
sed -i 's#</application>#<receiver android:name=".TarefasWidget" android:exported="true"><intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter><meta-data android:name="android.appwidget.provider" android:resource="@xml/widget_info"/></receiver><service android:name=".WidgetService" android:permission="android.permission.BIND_REMOTEVIEWS" android:exported="false"/><activity android:name=".WidgetClickActivity" android:theme="@android:style/Theme.NoDisplay" android:excludeFromRecents="true" android:exported="false"/></application>#' $M
# atalho do ícone (pressionar e segurar o ícone do app)
perl -0pi -e 's#</intent-filter>#</intent-filter><meta-data android:name="android.app.shortcuts" android:resource="\@xml/shortcuts"/>#' $M
grep -q "TarefasWidget" $M
grep -q "android.app.shortcuts" $M
echo "Widget, atalho e botão Feito criados"
