import { LogLevel, type Configuration, PublicClientApplication } from "@azure/msal-browser";

const clientId = import.meta.env.VITE_AZURE_CLIENT_ID as string | undefined;
const tenantId = import.meta.env.VITE_AZURE_TENANT_ID as string | undefined;
const apiScope = import.meta.env.VITE_AZURE_API_SCOPE as string | undefined;

if (!clientId || !tenantId) {
  // Intentionally loud so deployment config problems are obvious.
  // eslint-disable-next-line no-console
  console.warn("MSAL is missing VITE_AZURE_CLIENT_ID or VITE_AZURE_TENANT_ID.");
}

const authority = `https://login.microsoftonline.com/${tenantId ?? "common"}`;
const redirectUri = import.meta.env.VITE_AZURE_REDIRECT_URI || window.location.origin;

const config: Configuration = {
  auth: {
    clientId: clientId ?? "",
    authority,
    redirectUri,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
  system: {
    loggerOptions: {
      loggerCallback: (_level, _message, _containsPii) => {},
      piiLoggingEnabled: false,
      logLevel: LogLevel.Warning,
    },
  },
};

export const msalInstance = new PublicClientApplication(config);

export const loginRequest = {
  scopes: apiScope ? [apiScope] : [],
};

export const tokenRequest = {
  scopes: apiScope ? [apiScope] : [],
};
