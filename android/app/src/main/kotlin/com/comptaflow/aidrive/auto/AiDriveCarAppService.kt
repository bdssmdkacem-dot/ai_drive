package com.comptaflow.aidrive.auto

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Entry point Android Auto binds to. Registered in AndroidManifest.xml
 * under the `androidx.car.app.CarAppService` intent-filter.
 *
 * See docs/ANDROID_AUTO.md for the scope of what this module does (and
 * deliberately does not do) in v1.
 */
class AiDriveCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        // In debug builds, accept any host so you can test in Desktop Head
        // Unit / Android Auto emulator without extra setup. Before a real
        // release, switch to HostValidator.Builder(applicationContext)
        // .addAllowedHosts(R.array.hosts_allowlist_sample).build() — see
        // Android's official Car App Library sample for the allowlist XML
        // format, and docs/ANDROID_AUTO.md for the release checklist.
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        return AiDriveSession()
    }
}
