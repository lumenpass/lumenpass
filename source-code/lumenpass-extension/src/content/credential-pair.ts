/** Select a username and password from one form around the active field. */
export function selectCredentialPair<T extends { form: object | null }>(
  fields: T[],
  anchor: T,
  isUsername: (field: T) => boolean,
  isPassword: (field: T) => boolean,
  isFallbackUsername: (field: T) => boolean,
): { username: T | null; password: T | null } {
  const scoped = anchor.form
    ? fields.filter((field) => field.form === anchor.form)
    : fields;
  const anchorIndex = scoped.indexOf(anchor);
  const passwordFields = scoped.filter(isPassword);
  const password = isPassword(anchor)
    ? anchor
    : (passwordFields.find((field) => scoped.indexOf(field) > anchorIndex)
      ?? passwordFields[0]
      ?? null);
  const usernameCandidates = scoped.filter(
    (field) => field !== password && isUsername(field),
  );
  const fallbackCandidates = scoped.filter(
    (field) => field !== password && isFallbackUsername(field),
  );
  const candidates = usernameCandidates.length > 0
    ? usernameCandidates
    : fallbackCandidates;
  const referenceIndex = password ? scoped.indexOf(password) : anchorIndex;
  const beforePassword = candidates.filter(
    (field) => scoped.indexOf(field) < referenceIndex,
  );
  return {
    username: isUsername(anchor) ? anchor : (beforePassword.at(-1) ?? candidates[0] ?? null),
    password,
  };
}
