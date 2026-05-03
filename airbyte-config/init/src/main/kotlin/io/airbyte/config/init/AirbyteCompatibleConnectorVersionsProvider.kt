/*
 * Copyright (c) 2020-2026 Airbyte, Inc., all rights reserved.
 */

package io.airbyte.config.init

import dev.failsafe.Failsafe
import dev.failsafe.FailsafeExecutor
import dev.failsafe.RetryPolicy
import io.airbyte.commons.constants.AirbyteCatalogConstants
import io.airbyte.commons.json.Jsons
import io.airbyte.config.AirbyteCompatibleConnectorVersionsMatrix
import io.airbyte.config.ConnectorInfo
import io.airbyte.micronaut.runtime.AirbytePlatformCompatibilityConfig
import io.github.oshai.kotlinlogging.KotlinLogging
import io.micronaut.cache.annotation.CacheConfig
import io.micronaut.cache.annotation.Cacheable
import io.micronaut.context.annotation.Requires
import io.micronaut.http.HttpHeaders
import io.micronaut.http.MediaType
import jakarta.inject.Named
import jakarta.inject.Singleton
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.net.URI
import java.net.URL
import java.time.Duration

private val logger = KotlinLogging.logger {}

@Singleton
@CacheConfig("platform-compatibility-provider")
@Requires(property = "airbyte.edition", pattern = "(?i)^community|enterprise$")
open class AirbyteCompatibleConnectorVersionsProvider(
  @Named("platformCompatibilityClient") val okHttpClient: OkHttpClient,
  platformCompatibilityConfig: AirbytePlatformCompatibilityConfig,
) {
  private val remoteUrl: URL = run {
    val base = platformCompatibilityConfig.remote.baseUrl
      .takeIf { it.isNotBlank() }
      ?: AirbyteCatalogConstants.REMOTE_REGISTRY_BASE_URL
    URI("${base.trimEnd('/')}/${PLATFORM_COMPATIBILITY_PATH}").toURL()
  }

  @Cacheable
  open fun getCompatibleConnectorsMatrix(): Map<String, ConnectorInfo> {
    val request: Request =
      Request
        .Builder()
        .url(remoteUrl)
        .header(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON)
        .build()

    try {
      val responseSupplier = { okHttpClient.newCall(request).execute() }
      failsafe.get(responseSupplier).use { response ->
        if (response.isSuccessful && response.body != null) {
          val responseBody = response.body!!.string()
          val compatibleConnectorVersionsMatrix = Jsons.deserialize(responseBody, AirbyteCompatibleConnectorVersionsMatrix::class.java)
          return compatibleConnectorVersionsMatrix?.convertToMap() ?: emptyMap()
        } else {
          logger.warn {
            "Disabling compatibility validation: request to fetch platform compatibility matrix failed: " +
              "${response.code} with message: ${response.message}."
          }
          return emptyMap()
        }
      }
    } catch (e: Exception) {
      logger.warn { "Disabling compatibility validation: failed to fetch remote platform compatibility file: ${e.message}" }
      return emptyMap()
    }
  }

  companion object {
    internal const val PLATFORM_COMPATIBILITY_PATH = "platform/v0/platform-compatibility.json"

    fun AirbyteCompatibleConnectorVersionsMatrix.convertToMap(): Map<String, ConnectorInfo> =
      this.compatibleConnectors.associateBy { connectorInfo -> connectorInfo.connectorDefinitionId.toString() }

    val failsafe: FailsafeExecutor<Response> =
      Failsafe.with(
        RetryPolicy
          .builder<Response>()
          .withBackoff(Duration.ofMillis(10), Duration.ofMillis(100))
          .withMaxRetries(5)
          .build(),
      )
  }
}
