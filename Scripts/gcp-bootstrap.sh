#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# One-time setup of the mtats GCP project (spec §GCP resources). Idempotent where gcloud allows.
# Usage: BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX Scripts/gcp-bootstrap.sh
# Billing-isolation rule: every command passes --project explicitly; the default config is
# asserted unchanged at the end. Requires `npm ci` to have been run in site/ (pinned firebase-tools).
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-env.sh
P="$MTATS_GCP_PROJECT"; B="$MTATS_BUCKET"; SA="github-release@${P}.iam.gserviceaccount.com"
: "${BILLING_ACCOUNT:?set BILLING_ACCOUNT (gcloud billing accounts list)}"
DEFAULT_BEFORE=$(gcloud config get-value project 2>/dev/null)
trap '[[ "$(gcloud config get-value project 2>/dev/null)" == "$DEFAULT_BEFORE" ]] || echo "WARNING: gcloud default project changed!" >&2' EXIT

gcloud projects describe "$P" >/dev/null 2>&1 || gcloud projects create "$P" --name="mtats release" --labels=app=mtats
gcloud billing projects link "$P" --billing-account="$BILLING_ACCOUNT"
gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com iam.googleapis.com \
  iamcredentials.googleapis.com sts.googleapis.com storage.googleapis.com firebase.googleapis.com \
  firebasehosting.googleapis.com billingbudgets.googleapis.com --project "$P"
NUMBER=$(gcloud projects describe "$P" --format='value(projectNumber)')

gcloud storage buckets describe "gs://$B" --project "$P" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$B" --project "$P" --location=us-central1 --default-storage-class=STANDARD \
    --uniform-bucket-level-access --no-public-access-prevention
gcloud storage buckets update "gs://$B" --project "$P" --versioning
LC=$(mktemp); echo '{"rule":[{"action":{"type":"Delete"},"condition":{"daysSinceNoncurrentTime":90}}]}' >"$LC"
gcloud storage buckets update "gs://$B" --project "$P" --lifecycle-file="$LC"; rm -f "$LC"
gcloud storage buckets add-iam-policy-binding "gs://$B" --project "$P" --member=allUsers --role=roles/storage.objectViewer

gcloud iam service-accounts describe "$SA" --project "$P" >/dev/null 2>&1 || \
  gcloud iam service-accounts create github-release --project "$P" --display-name="GitHub release publisher"
# A new service account takes a few seconds to become visible to IAM bindings.
for _ in $(seq 12); do gcloud iam service-accounts describe "$SA" --project "$P" >/dev/null 2>&1 && break; sleep 5; done; sleep 10
gcloud storage buckets add-iam-policy-binding "gs://$B" --project "$P" --member="serviceAccount:$SA" --role=roles/storage.objectAdmin
gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$SA" --role=roles/firebasehosting.admin --condition=None
gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$SA" --role=roles/serviceusage.serviceUsageConsumer --condition=None

gcloud iam workload-identity-pools describe github --project "$P" --location=global >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools create github --project "$P" --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers describe github-oidc --project "$P" --location=global --workload-identity-pool=github >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-oidc github-oidc --project "$P" --location=global \
    --workload-identity-pool=github --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${MTATS_GITHUB_REPO}' && (assertion.ref.startsWith('refs/tags/v') || assertion.ref == 'refs/heads/main')"
gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$P" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/${MTATS_GITHUB_REPO}"

(cd site && npx firebase projects:addfirebase "$P") 2>/dev/null || echo "(Firebase already enabled on $P)"

gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --billing-project="$P" --format='value(displayName)' | grep -qx mtats-monthly || \
  gcloud billing budgets create --billing-account="$BILLING_ACCOUNT" --billing-project="$P" --display-name=mtats-monthly \
    --budget-amount=10USD --filter-projects="projects/${NUMBER}" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0

echo "GCP_WORKLOAD_IDENTITY_PROVIDER=projects/${NUMBER}/locations/global/workloadIdentityPools/github/providers/github-oidc"
echo "GCP_SERVICE_ACCOUNT=$SA"
