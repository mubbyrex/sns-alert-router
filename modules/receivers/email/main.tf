# Email receiver: subscribes each address to each subscribed tier's SNS topic.
#
# One aws_sns_topic_subscription per (tier x address) pair. The for_each key is
# the content-derived string "<tier>::<email>" rather than a positional index.
# Because for_each tracks resources by key, this means adding or removing a tier
# or an address only creates/destroys the affected subscriptions — every other
# subscription keeps its key and is left untouched. A positional key (e.g.
# count.index over a flattened list) would shift on any insert/removal and make
# Terraform destroy-and-recreate unrelated, still-wanted subscriptions.
#
# severity_tiers is validated (variables.tf) to be a subset of topic_arns'
# keys, so every topic_arns lookup below is guaranteed to resolve.
locals {
  subscriptions = {
    for pair in setproduct(var.severity_tiers, var.email_addresses) :
    "${pair[0]}::${pair[1]}" => {
      tier  = pair[0]
      email = pair[1]
    }
  }
}

resource "aws_sns_topic_subscription" "this" {
  for_each = local.subscriptions

  topic_arn = var.topic_arns[each.value.tier]
  protocol  = "email"
  endpoint  = each.value.email
}
