const ansiRegex = () =>
  new RegExp(
    '[\\u001B\\u009B][[\\]()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nq-uy=><]',
    'g'
  );

export default function stripAnsi(input) {
  if (typeof input !== 'string') {
    throw new TypeError('Expected a string');
  }

  return input.replace(ansiRegex(), '');
}

export { stripAnsi };
