import type { GeneratorType } from "./storage";

const LOWERCASE = "abcdefghijkmnopqrstuvwxyz";
const UPPERCASE = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const NUMBERS = "23456789";
const SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?";

export interface GeneratorConfig {
  length: number;
  includeUppercase: boolean;
  includeLowercase: boolean;
  includeNumbers: boolean;
  includeSymbols: boolean;
}

export function getGeneratorConfig(type: GeneratorType): GeneratorConfig {
  switch (type) {
    case "memorable":
      return {
        length: 16,
        includeUppercase: true,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: false,
      };
    case "pin":
      return {
        length: 8,
        includeUppercase: false,
        includeLowercase: false,
        includeNumbers: true,
        includeSymbols: false,
      };
    case "smart":
    default:
      return {
        length: 25,
        includeUppercase: true,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: true,
      };
  }
}

export function generatePassword(type: GeneratorType): string {
  const config = getGeneratorConfig(type);
  return generatePasswordFromConfig(config);
}

export function generatePasswordFromConfig(config: GeneratorConfig): string {
  const enabledPools = [
    config.includeLowercase ? LOWERCASE : "",
    config.includeUppercase ? UPPERCASE : "",
    config.includeNumbers ? NUMBERS : "",
    config.includeSymbols ? SYMBOLS : "",
  ].filter(Boolean);

  if (enabledPools.length === 0) {
    throw new Error("At least one character set must be enabled.");
  }

  const random = crypto.getRandomValues(new Uint32Array(config.length * 2 + enabledPools.length + 4));
  const combined = enabledPools.join("");
  const buffer: string[] = enabledPools.map(
    (pool, index) => pool[random[index] % pool.length],
  );

  while (buffer.length < config.length) {
    const index = random[buffer.length % random.length] % combined.length;
    buffer.push(combined[index]);
  }

  for (let i = buffer.length - 1; i > 0; i -= 1) {
    const swapIndex = random[i % random.length] % (i + 1);
    [buffer[i], buffer[swapIndex]] = [buffer[swapIndex], buffer[i]];
  }

  return buffer.join("");
}

export function describeGeneratorType(type: GeneratorType, domain?: string): string {
  switch (type) {
    case "memorable":
      return "A balanced password with letters and numbers that is easier to read.";
    case "pin":
      return "A numeric code for sites or apps that only accept PIN-style secrets.";
    case "smart":
    default:
      return domain
          ? `A strong password tuned for ${domain}, mixing multiple character sets.`
          : "A strong password that mixes letters, numbers, and symbols.";
  }
}
