import java.io.File;
import java.io.PrintWriter;
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
 * часу, прискорення та ефективності. Результати дублюються у файл results.csv.
 *
 * Кожна конфігурація міряється кілька разів: у хмарі одиничне вимірювання
 * ненадійне через сусідні віртуальні машини та розігрів JIT-компілятора.
 * За основну характеристику береться найкращий час, середній наводиться поряд.
 *
 * Формат вхідного файла input:
 *   number=4611685975477714963
 *   workers=1 2 4 8
 *   repeats=3
 */
public class Factorize {

    public static void main(String[] args) throws Exception {
        task curtask = new task();
        curtask.addJarFile("TrialDivision.jar");

        Settings settings = Settings.read(curtask.findFile("input"));
        long number = settings.number;
        int repeats = settings.repeats;

        long limit = integerSqrt(number);

        System.out.println("Число:            " + number);
        System.out.println("Межа перебору:    " + limit + " (цілий корінь)");
        System.out.println("Всього перевірок: " + (limit - 1));
        System.out.println("Повторів кожного вимірювання: " + repeats);
        System.out.println();

        AMInfo info = new AMInfo(curtask, null);

        System.out.println("Послідовний прохід...");
        long[] expected = null;
        long sequentialBest = Long.MAX_VALUE;
        long sequentialSum = 0;
        for (int r = 0; r < repeats; r++) {
            long started = System.currentTimeMillis();
            long[] found = scan(number, 2L, limit);
            long elapsed = System.currentTimeMillis() - started;
            if (expected == null) expected = found;
            if (elapsed < sequentialBest) sequentialBest = elapsed;
            sequentialSum += elapsed;
            System.out.println("  прохід " + (r + 1) + ": " + elapsed + " мс");
        }
        long sequentialMean = sequentialSum / repeats;
        System.out.println("  найкращий: " + sequentialBest + " мс, середній: " + sequentialMean + " мс");
        System.out.println("  дільників знайдено: " + expected.length);
        System.out.println("  розклад: " + factorization(number, expected));
        System.out.println();

        List<String[]> table = new ArrayList<String[]>();
        table.add(new String[] {
                "1 (посл.)", String.valueOf(sequentialBest), String.valueOf(sequentialMean),
                "1,00", "100,00", String.valueOf(expected.length), "еталон" });

        for (int i = 0; i < settings.workers.size(); i++) {
            int workers = settings.workers.get(i).intValue();
            System.out.println("Паралельний прохід, воркерів: " + workers);

            long best = Long.MAX_VALUE;
            long sum = 0;
            boolean allMatch = true;
            int divisorCount = 0;

            for (int r = 0; r < repeats; r++) {
                long started = System.currentTimeMillis();
                long[] found = runParallel(info, number, limit, workers);
                long elapsed = System.currentTimeMillis() - started;

                boolean same = sameValues(expected, found);
                if (!same) allMatch = false;
                divisorCount = found.length;
                if (elapsed < best) best = elapsed;
                sum += elapsed;

                System.out.println("  прохід " + (r + 1) + ": " + elapsed + " мс"
                        + (same ? "" : "  ЗБІГУ З ПОСЛІДОВНИМ НЕМАЄ"));
            }

            long mean = sum / repeats;
            double speedup = best == 0 ? 0.0 : (double) sequentialBest / (double) best;
            double efficiency = speedup / workers * 100.0;

            System.out.println("  найкращий: " + best + " мс, середній: " + mean
                    + " мс, прискорення: " + fmt(speedup));
            System.out.println();

            table.add(new String[] {
                    String.valueOf(workers), String.valueOf(best), String.valueOf(mean),
                    fmt(speedup), fmt(efficiency), String.valueOf(divisorCount),
                    allMatch ? "так" : "НІ" });
        }

        print(table);
        writeCsv(table, number, limit, repeats);

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
     * Цілий корінь без похибки з плаваючою комою: Math.sqrt для чисел порядку 10^18
     * може помилитися на одиницю, а від межі перебору залежить правильність відповіді.
     */
    private static long integerSqrt(long number) {
        long root = (long) Math.sqrt((double) number);
        while (root > 1 && root * root > number) root--;
        while ((root + 1) * (root + 1) <= number) root++;
        return root;
    }

    /**
     * Повний розклад на прості множники за знайденими дільниками.
     * Найменший знайдений дільник завжди простий, тому достатньо ділити на нього,
     * доки ділиться, і переходити до наступного.
     */
    private static String factorization(long number, long[] divisors) {
        if (divisors.length == 0) {
            return number + " — просте число";
        }
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
        return number + " = " + text.toString();
    }

    private static boolean sameValues(long[] a, long[] b) {
        if (a == null || b == null || a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    private static String fmt(double value) {
        return String.format("%.2f", Double.valueOf(value)).replace('.', ',');
    }

    private static void print(List<String[]> table) {
        String format = "%-10s %12s %12s %14s %15s %11s %8s";
        System.out.println("РЕЗУЛЬТАТИ");
        System.out.println(String.format(format,
                "воркерів", "найкр., мс", "сер., мс", "прискорення", "ефективність", "дільників", "збіг"));
        System.out.println(String.format(format,
                "--------", "----------", "--------", "-----------", "------------", "---------", "----"));
        for (int i = 0; i < table.size(); i++) {
            String[] r = table.get(i);
            System.out.println(String.format(format, r[0], r[1], r[2], r[3], r[4] + " %", r[5], r[6]));
        }
    }

    /** CSV для побудови графіка. Роздільник — крапка з комою, десятковий — крапка. */
    private static void writeCsv(List<String[]> table, long number, long limit, int repeats) {
        try {
            PrintWriter out = new PrintWriter("results.csv", "UTF-8");
            out.println("# число=" + number + "; межа=" + limit + "; повторів=" + repeats);
            out.println("воркерів;найкращий час, мс;середній час, мс;прискорення;ефективність, %;дільників;збіг");
            for (int i = 0; i < table.size(); i++) {
                String[] r = table.get(i);
                out.println(r[0] + ";" + r[1] + ";" + r[2] + ";" + r[3].replace(',', '.')
                        + ";" + r[4].replace(',', '.') + ";" + r[5] + ";" + r[6]);
            }
            out.close();
            System.out.println();
            System.out.println("Результати записано у results.csv");
        } catch (Exception e) {
            System.out.println("Не вдалося записати results.csv: " + e.getMessage());
        }
    }

    /** Розбір вхідного файла у форматі ключ=значення. */
    private static class Settings {
        long number = 4611685975477714963L;
        List<Integer> workers = new ArrayList<Integer>();
        int repeats = 1;

        static Settings read(String filename) throws Exception {
            Settings s = new Settings();
            Scanner sc = new Scanner(new File(filename));
            while (sc.hasNextLine()) {
                String line = sc.nextLine().trim();
                if (line.length() == 0 || line.startsWith("#")) continue;
                int eq = line.indexOf('=');
                if (eq < 0) continue;
                String key = line.substring(0, eq).trim();
                String value = line.substring(eq + 1).trim();

                if (key.equals("number")) {
                    s.number = Long.parseLong(value);
                } else if (key.equals("workers")) {
                    String[] parts = value.split("[\\s,]+");
                    for (int i = 0; i < parts.length; i++) {
                        if (parts[i].length() > 0) {
                            s.workers.add(Integer.valueOf(Integer.parseInt(parts[i])));
                        }
                    }
                } else if (key.equals("repeats")) {
                    s.repeats = Math.max(1, Integer.parseInt(value));
                }
            }
            sc.close();
            if (s.workers.isEmpty()) s.workers.add(Integer.valueOf(1));
            return s;
        }
    }
}
