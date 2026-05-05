# DevSecOps Azure Lab

This lab project demonstrates a DevSecOps workflow for Azure infrastructure using Kubernetes and cloud-native security tooling.

## Overview

The lab is built around Azure Kubernetes Service (AKS) and secures the deployment lifecycle using OpenID authentication, container scanning with Trivy, image signing with Cosign, policy enforcement with OPA Gatekeeper, GitOps deployments via ArgoCD, and continuous integration with GitHub Actions. The entire environment is maintained through Terraform with state stored in an Azure Storage Account for a reproducible and managed infrastructure lifecycle.

## Architecture

- Azure Kubernetes Service (AKS) for container orchestration
- Azure Active Directory / OpenID Connect for authentication and identity
- Trivy for vulnerability scanning of container images
- Cosign for signing and verifying container images
- OPA Gatekeeper for admission control and policy enforcement
- ArgoCD for GitOps-based application deployment and sync
- GitHub Actions for CI automation and pipeline orchestration
- Log Analytics for monitoring and diagnostics of cluster activity

## Components

- `AKS` - container platform running application workloads
- `OpenID` - identity provider integration for secure access
- `Trivy` - scans images for vulnerabilities and misconfigurations
- `Cosign` - signs images and validates provenance
- `OPA Gatekeeper` - enforces policies in the Kubernetes cluster
- `ArgoCD` - manages GitOps deployments and keeps cluster state in sync with Git
- `GitHub Actions` - handles CI workflows, builds, scans, signing, and deployment automation

## Prerequisites

- Azure subscription
- Azure CLI installed and logged in
- kubectl installed
- Helm installed
- Required Azure permissions to create AKS resources

## Setup

1. Create or use an existing Azure resource group.
2. Deploy AKS with cluster and node pool configuration.
3. Configure OpenID Connect or Azure AD integration for cluster authentication.
4. Install OPA Gatekeeper in the AKS cluster.
5. Install and configure ArgoCD for GitOps application delivery.
6. Configure GitHub Actions workflows to build, scan, sign, and deploy images.
7. Configure Trivy scanning for CI/CD image builds.
8. Use Cosign to sign images before pushing to Azure Container Registry.

## Security Workflow

- Build container images for the application in GitHub Actions.
- Scan images with Trivy to detect vulnerabilities.
- Sign images with Cosign to ensure integrity and provenance.
- Push signed images to Azure Container Registry.
- Trigger ArgoCD to deploy or sync Kubernetes manifests from Git.
- Deploy images to AKS only if they pass Trivy and Cosign checks.
- Enforce deployment policies in AKS using OPA Gatekeeper.

## Validation

- Verify AKS cluster is healthy.
- Ensure OPA Gatekeeper policies are loaded and active.
- Confirm images are scanned by Trivy.
- Validate image signatures with Cosign before deployment.
- Verify GitHub Actions CI workflows complete successfully.
- Confirm ArgoCD is syncing the GitOps application manifests to the cluster.

## Notes

This lab is designed as a reference for integrating Azure infrastructure with DevSecOps tooling to secure container deployments and enforce governance in Kubernetes. It also demonstrates GitOps with ArgoCD for declarative application delivery and GitHub Actions for automated CI workflows. The environment is created in the most cost-efficient way, using spot instances and usage alarms where appropriate, and can be recreated at any time from Terraform configurations while keeping state in Azure Storage Account. Log Analytics is used for monitoring and operational visibility.
