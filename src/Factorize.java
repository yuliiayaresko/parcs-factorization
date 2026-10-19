import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Scanner;
import parcs.*;

/**
 * Факторизація числа методом пробних дільників у системі ПАРКС.
 *
 * Кореневий модуль: читає вхідні дані, виконує послідовний еталонний прохід,
 * потім ту саму роботу для кожної заданої кількості воркерів і друкує таблицю
 * часу, прискорення та ефективності.
 *
 * Вхідний файл input:
 *   перший рядок  — число, яке факторизуємо;
 *   другий рядок  — кількості воркерів через пропуск, наприклад: 1 2 4 8
 */
public class Factorize {

    public static void main(String[] args) throws Exception {
        task curtask = new task();
        curtask.addJarFile("TrialDivision.jar");

        Scanner sc = new Scanner(new File(curtask.findFile("input")));
        long number = sc.nextLong();
        List<Integer> workerCounts = new ArrayList<Integer>();
        while (sc.hasNextInt()) {
            workerCounts.add(Integer.valueOf(sc.nextInt()));
        }
        sc.close();
        if (workerCounts.isEmpty()) {
            workerCounts.add(Integer.valueOf(1));
        }

        long limit = (long) Math.sqrt((double) number);
        while ((limit + 1) * (limit + 1) <= number) limit++;
        while (limit * limit > number) limit--;

        System.out.println("Число:           " + number);
        System.out.println("Межа перебору:   " + limit + " (цілий корінь)");
        System.out.println("Всього перевірок: " + (limit - 1));
        System.out.println();

        AMInfo info = new AMInfo(curtask, null);

        System.out.println("Послідовний прохід...");
        long sequentialStart = System.currentTimeMillis();
        long[] expected = scan(number, 2L, limit);
        long sequentialTime = System.currentTimeMillis() - sequentialStart;
        System.out.println("  час: " + sequentialTime + " мс, дільників знайдено: " + expected.length);
        System.out.println("  розклад: " + factorization(number, expected));
        System.out.println();

        List<String> rows = new ArrayList<String>();
        rows.add(row("воркерів", "час, мс", "прискорення", "ефективність", "дільників", "збіг"));
        rows.add(row("1 (посл.)", String.valueOf(sequentialTime), "1,00", "100 %",
                String.valueOf(expected.length), "еталон"));

        for (int i = 0; i < workerCounts.size(); i++) {
            int workers = workerCounts.get(i).intValue();
            System.out.println("Паралельний прохід, воркерів: " + workers);

            long start = System.currentTimeMillis();
            long[] found = runParallel(info, number, limit, workers);
            long elapsed = System.currentTimeMillis() - start;

            boolean same = sameValues(expected, found);
            double speedup = elapsed == 0 ? 0.0 : (double) sequentialTime / (double) elapsed;
            double efficiency = speedup / workers * 100.0;

            System.out.println("  час: " + elapsed + " мс, прискорення: " + fmt(speedup)
                    + ", збіг із послідовним: " + (same ? "так" : "НІ"));
            System.out.println();

            rows.add(row(String.valueOf(workers), String.valueOf(elapsed), fmt(speedup),
                    fmt(efficiency) + " %", String.valueOf(found.length), same ? "так" : "НІ"));
        }

        System.out.println("РЕЗУЛЬТАТИ");
        for (int i = 0; i < rows.size(); i++) {
            System.out.println(rows.get(i));
            if (i == 0) {
                System.out.println(row("--------", "-------", "-----------", "------------", "---------", "----"));
            }
        }

        curtask.end();
    }

    /** Розсилає відрізки воркерам, потім збирає відповіді. */
    private static long[] runParallel(AMInfo info, long number, long limit, int workers) {
        point[] points = new point[workers];
        channel[] channels = new channel[workers];

        long total = limit - 1;
        long chunk = total / workers;
        long rest = total % workers;
        long from = 2L;

        // Спершу запускаємо всі точки й роздаємо завдання, і лише потім читаємо відповіді.
        // Якщо читати одразу після кожного запуску, воркери виконувалися б по черзі.
        for (int i = 0; i < workers; i++) {
            long size = chunk + (i < rest ? 1 : 0);
            long to = from + size - 1;

            points[i] = info.createPoint();
            channels[i] = points[i].createChannel();
            points[i].execute("TrialDivision");
            channels[i].write(new long[] { number, from, to });

            from = to + 1;
        }

        List<Long> all = new ArrayList<Long>();
        for (int i = 0; i < workers; i++) {
            long[] part = (long[]) channels[i].readObject();
            for (int j = 0; j < part.length; j++) {
                all.add(Long.valueOf(part[j]));
            }
        }

        Collections.sort(all);
        long[] result = new long[all.size()];
        for (int i = 0; i < result.length; i++) {
            result[i] = all.get(i).longValue();
        }
        return result;
    }

    /** Послідовний перебір — еталон для порівняння часу й перевірки правильності. */
    private static long[] scan(long number, long from, long to) {
        List<Long> divisors = new ArrayList<Long>();
        for (long d = from; d <= to; d++) {
            if (number % d == 0) {
                divisors.add(Long.valueOf(d));
            }
        }
        long[] result = new long[divisors.size()];
        for (int i = 0; i < result.length; i++) {
            result[i] = divisors.get(i).longValue();
        }
        return result;
    }

    /**
     * Повний розклад на прості множники за знайденими дільниками.
     * Найменший знайдений дільник завжди простий, тому достатньо ділити на нього,
     * доки ділиться, і переходити до наступного.
     */
    private static String factorization(long number, long[] divisors) {
        long rest = number;
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < divisors.length; i++) {
            while (rest % divisors[i] == 0 && rest > 1) {
                if (text.length() > 0) text.append(" * ");
                text.append(divisors[i]);
                rest /= divisors[i];
            }
        }
        if (rest > 1) {
            if (text.length() > 0) text.append(" * ");
            text.append(rest);
        }
        if (divisors.length == 0) {
            return number + " — просте число";
        }
        return number + " = " + text.toString();
    }

    private static boolean sameValues(long[] a, long[] b) {
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    private static String fmt(double value) {
        return String.format("%.2f", Double.valueOf(value)).replace('.', ',');
    }

    private static String row(String a, String b, String c, String d, String e, String f) {
        return String.format("%-10s %10s %14s %15s %11s %8s", a, b, c, d, e, f);
    }
}
