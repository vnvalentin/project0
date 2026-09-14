extends GutTest
## Public-seam tests for Slice 051's environment-driven LocalLLMClient
## configuration (P-009). Cleans up any env vars it sets so other tests never
## observe leaked state.

const LocalLLMClientScript: Script = preload("res://shared/local_llm_client.gd")

const ENV_HOST: String = "PROJECT0_OLLAMA_HOST"
const ENV_MODEL: String = "PROJECT0_OLLAMA_MODEL"
const ENV_TIMEOUT: String = "PROJECT0_OLLAMA_TIMEOUT_SEC"


func _clear_env() -> void:
	for key in [ENV_HOST, ENV_MODEL, ENV_TIMEOUT]:
		OS.set_environment(key, "")


func after_each() -> void:
	_clear_env()


func test_resolve_config_defaults_when_env_unset() -> void:
	_clear_env()
	var config: Dictionary = LocalLLMClientScript.resolve_config()
	assert_eq(config["host"], "http://127.0.0.1:11434", "default host is the local Ollama address")
	assert_eq(config["model"], "llama3:latest", "default model matches the configured Llama model")
	assert_eq(config["timeout_sec"], 60.0, "default timeout matches the existing bounded HTTPRequest timeout")


func test_resolve_config_reads_env_overrides() -> void:
	OS.set_environment(ENV_HOST, "http://10.0.0.5:11434")
	OS.set_environment(ENV_MODEL, "llama3:70b")
	OS.set_environment(ENV_TIMEOUT, "12.5")

	var config: Dictionary = LocalLLMClientScript.resolve_config()
	assert_eq(config["host"], "http://10.0.0.5:11434", "resolve_config reads PROJECT0_OLLAMA_HOST")
	assert_eq(config["model"], "llama3:70b", "resolve_config reads PROJECT0_OLLAMA_MODEL")
	assert_eq(config["timeout_sec"], 12.5, "resolve_config reads PROJECT0_OLLAMA_TIMEOUT_SEC")


func test_resolve_config_rejects_non_finite_and_non_positive_timeout() -> void:
	OS.set_environment(ENV_TIMEOUT, "0")
	assert_eq(LocalLLMClientScript.resolve_config()["timeout_sec"], 60.0, "zero timeout falls back to default")

	OS.set_environment(ENV_TIMEOUT, "-5")
	assert_eq(LocalLLMClientScript.resolve_config()["timeout_sec"], 60.0, "negative timeout falls back to default")

	OS.set_environment(ENV_TIMEOUT, "not_a_number")
	assert_eq(LocalLLMClientScript.resolve_config()["timeout_sec"], 60.0, "non-numeric timeout falls back to default")

	OS.set_environment(ENV_TIMEOUT, "nan")
	assert_eq(LocalLLMClientScript.resolve_config()["timeout_sec"], 60.0, "NaN timeout falls back to default")


func test_configure_from_env_applies_env_when_exports_untouched() -> void:
	OS.set_environment(ENV_HOST, "http://10.0.0.9:11434")
	OS.set_environment(ENV_MODEL, "llama3:custom")
	OS.set_environment(ENV_TIMEOUT, "5.0")

	var client: Node = LocalLLMClientScript.new()
	client.configure_from_env()

	assert_eq(client.ollama_host, "http://10.0.0.9:11434", "configure_from_env applies env host to an untouched export")
	assert_eq(client.model_name, "llama3:custom", "configure_from_env applies env model to an untouched export")
	assert_eq(client.request_timeout_sec, 5.0, "configure_from_env applies env timeout to an untouched export")

	client.free()


func test_configure_from_env_preserves_explicit_caller_assignment() -> void:
	OS.set_environment(ENV_HOST, "http://10.0.0.9:11434")
	OS.set_environment(ENV_MODEL, "llama3:custom")
	OS.set_environment(ENV_TIMEOUT, "5.0")

	var client: Node = LocalLLMClientScript.new()
	client.ollama_host = "http://192.168.1.1:11434"
	client.model_name = "llama3:explicit"
	client.request_timeout_sec = 30.0
	client.configure_from_env()

	assert_eq(client.ollama_host, "http://192.168.1.1:11434", "explicit ollama_host assignment wins over env config")
	assert_eq(client.model_name, "llama3:explicit", "explicit model_name assignment wins over env config")
	assert_eq(client.request_timeout_sec, 30.0, "explicit request_timeout_sec assignment wins over env config")

	client.free()
