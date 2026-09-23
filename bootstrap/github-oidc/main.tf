provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "poc-gvr"
      ManagedBy = "terraform"
      Layer     = "bootstrap-oidc"
    }
  }
}

locals {
  repo = "${var.github_owner}/${var.github_repo}"

  # GitHub immutable OIDC subject: repo:<owner>@<owner-id>/<repo>@<repo-id>

  sub_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# - url is GitHub's token issuer. AWS fetches GitHub's public keys from it to check token signatures.
# - client_id_list is the audience (aud) the tokens must carry. The official AWS action requests sts.amazonaws.com.
# - Older guides also set thumbprint_list. AWS now validates GitHub's certificate itself, so provider v6 doesn't need it.


data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.sub_prefix}:pull_request",
        "${local.sub_prefix}:ref:refs/heads/*",
      ]
    }
  }
}


resource "aws_iam_role" "plan" {
  name                 = "gha-eks-infra-plan"
  description          = "GitHub Actions: terraform plan (read-only) for ${local.repo}"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# plan only reads state, but it must create and delete the .tflock file
data "aws_iam_policy_document" "plan_state_lock" {
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/*.tflock"]
  }
}


# - Trust policy (assume_role_policy) answers who may use this role. Permission policies (the attachment and the inline policy) answer what the role can do. They're two separate questions.
# - principals { type = "Federated" } means "an identity from an outside provider", here GitHub.
# - There are two conditions, and both must match:
#   - aud: the token was meant for AWS STS.
#   - sub: it comes from your repo, as a PR or from any branch. StringLike allows the * wildcard; StringEquals doesn't.
# - Never use repo:* or leave out the sub condition. Without it, any GitHub repo in the world could assume your role.
# - ReadOnlyAccess is an AWS-managed policy. It covers reading the infrastructure and the state file. The small inline policy adds write access only for *.tflock files, which plan needs to take its lock.
# - max_session_duration = 3600: the credentials expire after 1 hour.


##-------------------------- Apply roles: one per GitHub Environment---------------------

data "aws_iam_policy_document" "apply_trust" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.sub_prefix}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  for_each = var.environments

  name                 = "gha-eks-infra-apply-${each.key}"
  description          = "GitHub Actions: terraform apply for the ${each.key} environment"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust[each.key].json
  max_session_duration = 3600
}


resource "aws_iam_role_policy" "plan_state_lock" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state_lock.json
}

# POC only: broad permissions so Terraform can create VPC, EKS, RDS, IAM roles, ...
# Tighten later with a permissions boundary or a scoped policy.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  for_each = var.environments

  role       = aws_iam_role.apply[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}