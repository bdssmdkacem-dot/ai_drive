package com.comptaflow.aidrive.auto

import androidx.car.app.Screen
import androidx.car.app.Session
import android.content.Intent

class AiDriveSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return MainCarScreen(carContext)
    }
}
