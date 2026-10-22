package io.ansi.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.MealType
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Mass
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.launch

/**
 * A FlutterFragmentActivity, not a FlutterActivity: Health Connect asks for
 * permission through an ActivityResult contract, which needs a fragment
 * activity to register against.
 *
 * The `io.ansi.app/health` channel is Ansi's whole use of Health Connect:
 * write-only, nutrition only, one record per meal per member, each carrying
 * its own client record id so a later write replaces it and a delete can name
 * it (`features/health`).
 */
class MainActivity : FlutterFragmentActivity() {
    private val writeNutrition =
        HealthPermission.getWritePermission(NutritionRecord::class)
    private var pendingPermission: MethodChannel.Result? = null
    private lateinit var permissionLauncher: ActivityResultLauncher<Set<String>>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        permissionLauncher = registerForActivityResult(
            PermissionController.createRequestPermissionResultContract(),
        ) { granted ->
            pendingPermission?.success(granted.contains(writeNutrition))
            pendingPermission = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.ansi.app/health")
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> result.success(
                when (HealthConnectClient.getSdkStatus(this)) {
                    HealthConnectClient.SDK_AVAILABLE -> "available"
                    HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "needs_update"
                    else -> "unavailable"
                },
            )
            "canWrite" -> withClient(result) { client ->
                result.success(
                    client.permissionController.getGrantedPermissions()
                        .contains(writeNutrition),
                )
            }
            "requestWrite" -> {
                if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
                    result.success(false)
                } else {
                    pendingPermission?.success(false)
                    pendingPermission = result
                    permissionLauncher.launch(setOf(writeNutrition))
                }
            }
            "write" -> withClient(result) { client ->
                @Suppress("UNCHECKED_CAST")
                val meals = call.arguments as List<Map<String, Any?>>
                client.insertRecords(meals.map(::nutritionRecord))
                result.success(null)
            }
            "delete" -> withClient(result) { client ->
                @Suppress("UNCHECKED_CAST")
                val ids = call.arguments as List<String>
                client.deleteRecords(
                    NutritionRecord::class,
                    recordIdsList = emptyList(),
                    clientRecordIdsList = ids,
                )
                result.success(null)
            }
            "openSettings" -> {
                startActivity(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [block] against Health Connect, reporting any failure to Dart. */
    private fun withClient(
        result: MethodChannel.Result,
        block: suspend (HealthConnectClient) -> Unit,
    ) {
        if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
            result.error("unavailable", "Health Connect is not available", null)
            return
        }
        lifecycleScope.launch {
            try {
                block(HealthConnectClient.getOrCreate(this@MainActivity))
            } catch (e: Exception) {
                result.error("health", e.message, null)
            }
        }
    }

    /** One meal, as the Dart side describes it, as a nutrition record. */
    private fun nutritionRecord(m: Map<String, Any?>): NutritionRecord {
        val at = Instant.ofEpochMilli((m["at"] as Number).toLong())
        // An instant, not a span: a minute is the shortest honest interval.
        val end = at.plusSeconds(60)
        val zone = ZoneId.systemDefault().rules
        fun grams(key: String) = (m[key] as Number?)?.let { Mass.grams(it.toDouble()) }
        return NutritionRecord(
            startTime = at,
            startZoneOffset = zone.getOffset(at),
            endTime = end,
            endZoneOffset = zone.getOffset(end),
            metadata = Metadata.manualEntry(
                clientRecordId = m["id"] as String,
                clientRecordVersion = (m["version"] as Number).toLong(),
            ),
            name = m["name"] as String?,
            mealType = when (m["mealType"] as String?) {
                "breakfast" -> MealType.MEAL_TYPE_BREAKFAST
                "lunch" -> MealType.MEAL_TYPE_LUNCH
                "dinner" -> MealType.MEAL_TYPE_DINNER
                "snack" -> MealType.MEAL_TYPE_SNACK
                else -> MealType.MEAL_TYPE_UNKNOWN
            },
            energy = (m["kcal"] as Number?)?.let { Energy.kilocalories(it.toDouble()) },
            protein = grams("protein"),
            totalCarbohydrate = grams("carb"),
            totalFat = grams("fat"),
            dietaryFiber = grams("fiber"),
        )
    }
}
