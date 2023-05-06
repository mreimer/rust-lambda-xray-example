use lambda_runtime::{service_fn, LambdaEvent, Error};
use anyhow::{Context, Result};
use serde_json::{json, Value};
use opentelemetry::sdk::Resource;
use opentelemetry::KeyValue;
use opentelemetry::{global, sdk::trace};
use opentelemetry_aws::trace::XrayPropagator;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_semantic_conventions as semcov;
use tracing::info;
use tracing_subscriber::prelude::*;
use tracing_subscriber::Registry;
use tracing_subscriber::{fmt, EnvFilter};
use tracing::instrument;

fn opentelemetry_tracer(app_name: &str, version: &str) -> Result<trace::Tracer> {
    global::set_text_map_propagator(XrayPropagator::new());

    let environment = match std::env::var("DEPLOYMENT_ENVIRONMENT") {
        Ok(env) => env,
        _ => "dev".to_string(),
    };

    opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(opentelemetry_otlp::new_exporter().tonic().with_env())
        .with_trace_config(
            trace::config()
                .with_resource(Resource::new(vec![
                    KeyValue::new(
                        semcov::resource::SERVICE_NAME.to_string(),
                        app_name.to_string(),
                    ),
                    KeyValue::new(
                        semcov::resource::SERVICE_VERSION.to_string(),
                        version.to_string(),
                    ),
                    KeyValue::new(
                        semcov::resource::SERVICE_INSTANCE_ID.to_string(),
                        gethostname::gethostname().to_string_lossy().to_string(),
                    ),
                    KeyValue::new(semcov::resource::SERVICE_NAMESPACE.to_string(), environment),
                ]))
                .with_sampler(trace::Sampler::AlwaysOn)
                // Needed in order to convert the trace IDs into an Xray-compatible format
                .with_id_generator(trace::XrayIdGenerator::default()),
        )
        .install_batch(opentelemetry::runtime::Tokio)
        .context("Failed to install tracer")
}

pub fn tracer_init(tracer: trace::Tracer) {
    let telemetry = tracing_opentelemetry::layer().with_tracer(tracer);

    Registry::default()
        .with(
            EnvFilter::builder()
                .with_default_directive("info".parse().unwrap())
                .from_env_lossy(),
        )
        .with(telemetry)
        .with(fmt::layer().without_time().json())
        .init();
}

//#[instrument]
async fn handler(event: LambdaEvent<Value>) -> Result<Value, Error> {
    let (event, _context) = event.into_parts();
    let first_name = event["firstName"].as_str().unwrap_or("world");

    Ok(json!({ "message": format!("Hello, {}!", first_name) }))
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    let tracer = opentelemetry_tracer("lambda-xray", "0.0.1").context("Couldn't get tracer")?;
    let provider = tracer
        .provider()
        .context("Couldn't get provider from tracer")?;
//    tracer_init(tracer);

    info!("Starting up.");

    let func = service_fn(|event| {
        let result = handler(event);
        info!("Flushing traces.");
        provider.force_flush();
        info!("Flush complete.");
        result
    });

    lambda_runtime::run(func).await?;

    info!("Shutting down.");
    global::shutdown_tracer_provider();

    Ok(())
}
