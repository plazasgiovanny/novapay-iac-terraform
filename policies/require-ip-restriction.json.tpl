{
  "if": {
    "allOf": [
      {
        "field": "type",
        "equals": "Microsoft.Web/sites/config"
      },
      {
        "anyOf": [
          {
            "field": "id",
            "like": "*/func-novapay-pagos-${environment}/config/web"
          },
          {
            "field": "id",
            "like": "*/func-novapay-pagos-canary-${environment}/config/web"
          }
        ]
      },
      {
        "not": {
          "field": "Microsoft.Web/sites/config/web.ipSecurityRestrictionsDefaultAction",
          "equals": "Deny"
        }
      }
    ]
  },
  "then": {
    "effect": "Deny"
  }
}
