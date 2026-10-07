# Email signatures

Copy this file to `signatures.md` in this folder (gitignored) and replace the examples with your own signatures.
Used by `/draft-email`. Gmail doesn't add signatures to drafts created through the connector, so the skill pastes the right one into the body, below the sign-off.

## Which signature to use

1. **New email** (not a reply): `full`
2. **Reply** to an existing thread: `short`

If the user asks for a specific signature, or for none, do that instead.

## Signatures

Give each signature a `###` heading with its name, followed by a code block with the exact text.

### full

```
--
Jane Doe
Assistant Professor, Department of Example
Example University
janedoe.com
```

### short

```
--
Jane Doe
janedoe.com
```
