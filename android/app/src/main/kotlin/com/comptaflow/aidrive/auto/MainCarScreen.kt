package com.comptaflow.aidrive.auto

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import com.comptaflow.aidrive.R

/**
 * The car screen shown when AI Drive Assistant is opened on Android Auto.
 *
 * Scope note (see docs/ANDROID_AUTO.md): this is a list-based action
 * screen, not a full turn-by-turn NavigationTemplate implementation.
 * "Navigate Home"/"Navigate Work" hand off to the device's default map
 * app via a geo intent rather than rendering routing on the car's own
 * screen — that's the fastest path to something genuinely useful on the
 * car display without reimplementing turn-by-turn guidance a second time
 * (Google Maps / the phone's Navigation screen already does this well).
 * Live camera / dashcam features are intentionally NOT exposed here, per
 * Android Auto's distraction guidelines and the architecture doc's own
 * "not suitable for Android Auto" list.
 */
class MainCarScreen(carContext: CarContext) : Screen(carContext) {

    // Reads the same keys the Flutter app's SettingsScreen writes via
    // SharedPreferences (home_address / work_address). This relies on the
    // shared_preferences plugin's legacy Android storage format (plain
    // SharedPreferences file "FlutterSharedPreferences", keys prefixed
    // "flutter."). If you upgrade the shared_preferences plugin to a
    // version that defaults to Jetpack DataStore, this read will silently
    // return null — re-verify against that plugin version's storage
    // format before relying on this in production, or replace it with an
    // explicit MethodChannel bridge for a version-proof approach.
    private fun readFlutterPref(key: String): String? {
        val prefs = carContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getString("flutter.$key", null)
    }

    override fun onGetTemplate(): Template {
        val itemList = ItemList.Builder()
            .addItem(navigationRow("Navigate Home", "home_address"))
            .addItem(navigationRow("Navigate Work", "work_address"))
            .addItem(searchRow("Nearby Parking", "parking"))
            .addItem(searchRow("Nearby Gas Station", "gas station"))
            .addItem(
                Row.Builder()
                    .setTitle("Dashcam & driver monitoring")
                    .addText("Manage from your phone while parked")
                    .build()
            )
            .build()

        return ListTemplate.Builder()
            .setSingleList(itemList)
            .setTitle(carContext.getString(R.string.app_name))
            .setHeaderAction(Action.APP_ICON)
            .build()
    }

    private fun navigationRow(title: String, prefKey: String): Row {
        return Row.Builder()
            .setTitle(title)
            .setOnClickListener {
                val address = readFlutterPref(prefKey)
                if (address.isNullOrBlank()) {
                    CarToast.makeText(
                        carContext,
                        "Set your $title address in the AI Drive Assistant app first",
                        CarToast.LENGTH_LONG
                    ).show()
                } else {
                    launchNavigation(Uri.encode(address))
                }
            }
            .build()
    }

    private fun searchRow(title: String, query: String): Row {
        return Row.Builder()
            .setTitle(title)
            .setOnClickListener { launchNavigation(Uri.encode(query), isSearch = true) }
            .build()
    }

    private fun launchNavigation(encodedQuery: String, isSearch: Boolean = false) {
        val geoUri = if (isSearch) {
            "geo:0,0?q=$encodedQuery"
        } else {
            "geo:0,0?q=$encodedQuery"
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(geoUri))
        intent.setPackage("com.google.android.apps.maps")
        try {
            carContext.startCarApp(intent)
        } catch (e: ActivityNotFoundException) {
            // Fall back to whatever handles geo: intents if Google Maps
            // isn't installed.
            carContext.startCarApp(Intent(Intent.ACTION_VIEW, Uri.parse(geoUri)))
        }
    }
}
