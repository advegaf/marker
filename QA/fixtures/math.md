# Math

Inline math like $E = mc^2$ inside a sentence, and $\alpha + \beta = \gamma$ next
to it, and a subscript $x_{1}$ with a fraction $\frac{a}{b}$.

Prices must not become formulas: it costs $5 and $10, which is $15 in total.

Escaped delimiters stay literal: \$not math\$.

## Display

$$
\int_{0}^{1} x^2 \, dx = \frac{1}{3}
$$

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$

$$
\begin{pmatrix} a & b \\ c & d \end{pmatrix}
\begin{pmatrix} x \\ y \end{pmatrix}
$$

## Broken on purpose

Inline that will not parse: $\thisIsNotACommand{x}$ should fall back to source.

$$
\frac{1}{
$$

## Inside other things

- A list item with $\sqrt{2}$ in it
- **Bold text with $\pi r^2$ inside**

> A quote containing $\lim_{x \to 0} \frac{\sin x}{x} = 1$.

Code stays code: `$PATH` and `$HOME` are shell variables, not math.
