import java.util.ArrayList;
import java.util.List;
import parcs.*;

/**
 * Воркер. Отримує число та свій відрізок дільників, перебирає його
 * і повертає ті дільники, які знайшов.
 *
 * Обсяг даних, що йдуть мережею, не залежить від обсягу обчислень:
 * у кожен бік передається кілька чисел, а роботи — мільярди операцій остачі.
 * Саме тому задача добре лягає на розподілену систему.
 */
public class TrialDivision implements AM {

    public void run(AMInfo info) {
        long[] request = (long[]) info.parent.readObject();
        long number = request[0];
        long from = request[1];
        long to = request[2];

        long started = System.currentTimeMillis();
        List<Long> divisors = new ArrayList<Long>();

        for (long d = from; d <= to; d++) {
            if (number % d == 0) {
                divisors.add(d);
            }
        }

        long elapsed = System.currentTimeMillis() - started;
        System.out.println("[" + from + ".." + to + "] перевірено "
                + (to - from + 1) + " дільників за " + elapsed + " мс, знайдено " + divisors.size());

        long[] result = new long[divisors.size()];
        for (int i = 0; i < result.length; i++) {
            result[i] = divisors.get(i).longValue();
        }
        info.parent.write(result);
    }
}
