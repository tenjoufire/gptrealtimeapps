import { DefaultAzureCredential } from "@azure/identity";

import { config } from "./config.js";

export const credential = config.azureClientId
  ? new DefaultAzureCredential({
      managedIdentityClientId: config.azureClientId
    })
  : new DefaultAzureCredential();