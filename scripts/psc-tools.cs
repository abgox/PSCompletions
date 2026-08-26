// Compiled at runtime via Add-Type by scripts/*.ps1 (no build step required).
//
// SortCheck: read-only check whether a parsed manifest is already in the exact
//   form sort-json.ps1's rebuild produces. A null verdict must GUARANTEE that:
//   when in doubt, report a violation — falling back to the rebuild only costs
//   time, while a wrong "canonical" skips necessary writes.
// Diff: structural/translation differ for compare-json.ps1.
namespace PscTools {
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Management.Automation;
    using System.Text.RegularExpressions;

    // Canonicality checker for sort-json: returns null when the tree already has
    // exactly the form the rebuild would produce, else a short reason string.
    public static class SortCheck
    {
        static readonly string[] TopLevel = { "meta", "next", "option", "global_option", "config", "info" };
        static readonly string[] MetaOrder = { "url", "description" };
        static readonly string[] ConfigOrder = { "name", "value", "values", "tip" };
        static readonly string[] ItemOrder = { "name", "alias", "usage", "tip", "example", "repeat", "option", "next" };

        sealed class Ctx
        {
            public string[] Order;
            public bool Nog;   // inside next/option/global_option subtree: alias/usage rules apply
        }

        public static string CheckCanonical(object root)
        {
            try { return CheckRoot(root); }
            catch (Exception) { return "checker error"; }   // any surprise -> take the safe slow path
        }

        static string CheckRoot(object root)
        {
            var pso = PSObject.AsPSObject(root);
            var names = PropNames(pso);

            var expected = new List<string>();
            foreach (var n in TopLevel) if (names.Contains(n)) expected.Add(n);
            var extras = new List<string>();
            foreach (var n in names) if (Array.IndexOf(TopLevel, n) < 0) extras.Add(n);
            extras.Sort(CompareNames);
            expected.AddRange(extras);

            for (int i = 0; i < Math.Max(names.Count, expected.Count); i++)
            {
                var a = i < names.Count ? names[i] : null;
                var b = i < expected.Count ? expected[i] : null;
                if (!string.Equals(a, b, StringComparison.Ordinal)) return "root property order";
            }

            foreach (var section in TopLevel)
            {
                if (!names.Contains(section)) continue;
                var value = PropValue(pso, section);
                string v;
                switch (section)
                {
                    case "meta":
                        v = CheckValue(value, new Ctx { Order = MetaOrder, Nog = false }, section); break;
                    case "config":
                        v = CheckValue(Wrap(value), new Ctx { Order = ConfigOrder, Nog = false }, section); break;
                    case "next":
                    case "option":
                    case "global_option":
                        v = CheckValue(Wrap(value), new Ctx { Order = ItemOrder, Nog = true }, section); break;
                    default:
                        v = CheckValue(value, new Ctx { Order = new string[0], Nog = false }, section); break;
                }
                if (v != null) return v;
            }
            foreach (var n in extras)
            {
                var v = CheckValue(PropValue(pso, n), new Ctx { Order = new string[0], Nog = false }, n);
                if (v != null) return v;
            }
            return null;
        }

        static string CheckValue(object value, Ctx ctx, string path)
        {
            if (value == null) return null;
            var arr = AsArray(value);
            if (arr != null) return CheckArray(arr, ctx, path);
            if (value is PSObject || IsJsonObject(value)) return CheckObject(PSObject.AsPSObject(value), ctx, path);
            return null;   // scalar leaf
        }

        static string CheckArray(IList arr, Ctx ctx, string path)
        {
            if (arr.Count > 0 && HasName(arr[0]))
            {
                for (int i = 1; i < arr.Count; i++)
                {
                    if (!HasName(arr[i])) return path + "[" + i + "] missing name";
                    if (CompareNamed(arr[i - 1], arr[i]) > 0) return path + " not name-sorted @" + i;
                }
            }
            for (int i = 0; i < arr.Count; i++)
            {
                var v = CheckValue(arr[i], ctx, path + "[" + i + "]");
                if (v != null) return v;
            }
            return null;
        }

        static string CheckObject(PSObject pso, Ctx ctx, string path)
        {
            var names = PropNames(pso);

            if (ctx.Nog)
            {
                var av = CheckAliasUsage(pso, names, path);
                if (av != null) return av;
            }

            var expected = new List<string>();
            foreach (var n in ctx.Order) if (names.Contains(n)) expected.Add(n);
            var extras = new List<string>();
            foreach (var n in names) if (Array.IndexOf(ctx.Order, n) < 0) extras.Add(n);
            extras.Sort(CompareNames);
            expected.AddRange(extras);

            for (int i = 0; i < Math.Max(names.Count, expected.Count); i++)
            {
                var a = i < names.Count ? names[i] : null;
                var b = i < expected.Count ? expected[i] : null;
                if (!string.Equals(a, b, StringComparison.Ordinal)) return path + " property order";
            }

            foreach (var n in names)
            {
                var v = CheckValue(PropValue(pso, n), ctx, path + ">" + n);
                if (v != null) return v;
            }
            return null;
        }

        static string CheckAliasUsage(PSObject pso, List<string> names, string path)
        {
            // alias: [name]+alias must be non-increasing by length (stable sort fixed point)
            if (names.Contains("alias"))
            {
                var alias = AsArray(PropValue(pso, "alias")) ?? Singleton(PropValue(pso, "alias"));
                if (alias != null && alias.Count > 0)
                {
                    var prev = TextLen(NameOf(pso));
                    for (int i = 0; i < alias.Count; i++)
                    {
                        var len = TextLen(alias[i]);
                        if (len > prev) return path + " alias not longest-first @" + i;
                        prev = len;
                    }
                }
            }
            // usage lines: leading separator block must be non-decreasing by form length
            if (names.Contains("usage"))
            {
                var uv = PropValue(pso, "usage");
                var usage = AsArray(uv) ?? Singleton(uv);
                if (usage != null)
                {
                    for (int i = 0; i < usage.Count; i++)
                    {
                        var s = usage[i] as string;
                        if (s == null) continue;
                        var v = CheckUsageLine(s);
                        if (v != null) return path + " usage[" + i + "] " + v;
                    }
                }
            }
            return null;
        }

        static string CheckUsageLine(string u)
        {
            var m = UsageBlockRegex.Match(u);
            if (!m.Success) return null;
            var block = m.Value;
            var hasPipe = block.IndexOf('|') >= 0;
            var hasComma = block.IndexOf(',') >= 0;
            if (hasPipe && hasComma) return null;   // mixed separators, skipped by optimizer
            if (!hasPipe && !hasComma) return null; // single form
            var parts = block.Split('|', ',');
            int prev = -1;
            foreach (var p in parts)
            {
                var t = p.Trim();
                if (t.Length == 0) continue;
                if (t.Length < prev) return "forms not short-to-long";
                prev = t.Length;
            }
            return null;
        }

        static readonly Regex UsageBlockRegex =
            new Regex("^([^\\s,|<=\\[|]+(?:\\s*[,|]\\s*[^\\s,|<=\\[|]+)*)");

        // ---- helpers ----

        static IList Wrap(object v) { return AsArray(v) ?? new object[] { v }; }

        static IList Singleton(object v) { return v == null ? null : new object[] { v }; }

        static int TextLen(object o) { return (o as string)?.Length ?? 0; }

        static string NameOf(PSObject pso)
        {
            foreach (var p in pso.Properties)
                if (p.Name == "name") return p.Value as string;
            return null;
        }

        static bool HasName(object o)
        {
            var pso = o as PSObject;
            if (pso == null) return false;
            foreach (var p in pso.Properties)
                if (p.Name == "name") return true;
            return false;
        }

        // name ordering used across all manifests: culture-aware (upper(name), name)
        static int CompareNamed(object a, object b)
        {
            var na = NameOf(PSObject.AsPSObject(a));
            var nb = NameOf(PSObject.AsPSObject(b));
            var ua = na?.ToUpperInvariant();
            var ub = nb?.ToUpperInvariant();
            int c = string.Compare(ua, ub, StringComparison.CurrentCulture);
            if (c != 0) return c;
            return string.Compare(na, nb, StringComparison.CurrentCulture);
        }

        static int CompareNames(string a, string b)
        {
            int c = string.Compare(a?.ToUpperInvariant(), b?.ToUpperInvariant(), StringComparison.CurrentCulture);
            if (c != 0) return c;
            return string.Compare(a, b, StringComparison.CurrentCulture);
        }

        static List<string> PropNames(PSObject pso)
        {
            var list = new List<string>();
            foreach (var p in pso.Properties) list.Add(p.Name);
            return list;
        }

        static object PropValue(PSObject pso, string name)
        {
            foreach (var p in pso.Properties)
                if (p.Name == name) return p.Value;
            return null;
        }

        static IList AsArray(object o)
        {
            if (o is string) return null;
            var list = o as IList;
            if (list != null) return list;
            var pso = o as PSObject;
            if (pso != null)
            {
                var inner = pso.BaseObject as IList;
                if (inner != null && !(pso.BaseObject is string)) return inner;
            }
            return null;
        }

        static bool IsJsonObject(object o)
        {
            if (o is string || o is ValueType) return false;
            return true;
        }
    }

    // Structural/translation differ: walks both trees together and records every
    // difference (missing/extra items, type mismatches, value diffs, untranslated
    // text, usage-rule violations). Input trees come from ConvertFrom-Json
    // -AsHashtable; issue order follows the trees' natural enumeration order.
    public sealed class DiffIssue
    {
        public string Path;
        public string Name;
        public string Reason;
    }

    public sealed class DiffStats
    {
        public List<DiffIssue> MissingInTarget = new List<DiffIssue>();
        public List<DiffIssue> ExtraInTarget = new List<DiffIssue>();
        public List<DiffIssue> TypeMismatch = new List<DiffIssue>();
        public List<DiffIssue> SemanticMismatch = new List<DiffIssue>();
        public List<DiffIssue> ValueDiff = new List<DiffIssue>();
        public List<DiffIssue> Untranslated = new List<DiffIssue>();
        public List<DiffIssue> DuplicateItems = new List<DiffIssue>();
        public List<DiffIssue> MeaninglessUsage = new List<DiffIssue>();
        public List<DiffIssue> MissingUsage = new List<DiffIssue>();
        public List<DiffIssue> DuplicateOptions = new List<DiffIssue>();
        public List<DiffIssue> UsageOrder = new List<DiffIssue>();
        public List<DiffIssue> UsageTooSimple = new List<DiffIssue>();
        public List<DiffIssue> UsageSeparator = new List<DiffIssue>();
        public List<DiffIssue> OptionMissingNext = new List<DiffIssue>();
        public List<DiffIssue> ForbiddenEmptyNext = new List<DiffIssue>();
        public List<DiffIssue> UsageRootPrefix = new List<DiffIssue>();
        public long TotalTips;
        public long TranslatedTips;
    }

    public sealed class DiffOptions
    {
        public string BaseLang;
        public string TargetLang;
        public string CompletionName;
        public string ReasonCount;
        public string ReasonType;
        public string ReasonMissingField;
        public string ReasonCmdValue;
        public string ReasonNextValue;
    }

    public static class Diff
    {
        static DiffOptions Opts;
        static DiffStats S;

        const string Red = "<@Red>";
        const string Cyan = "<@Cyan>";

        public static DiffStats Run(object baseTree, object targetTree, DiffOptions opts)
        {
            Opts = opts;
            S = new DiffStats();
            ValidateOptions((IDictionary)baseTree);
            ValidateAllTips((IDictionary)baseTree, "", false, false);
            ValidateAllTips((IDictionary)targetTree, "", false, false);
            CompareFields((IDictionary)baseTree, (IDictionary)targetTree, "", false);
            return S;
        }

        // ---- equality: strings case-insensitive + culture-aware, numbers numeric ----

        static bool PsEqual(object a, object b)
        {
            if (a == null || b == null) return a == null && b == null;
            var sa = a as string;
            var sb = b as string;
            if (sa != null || sb != null)
                return sa != null && sb != null && string.Equals(sa, sb, StringComparison.CurrentCultureIgnoreCase);
            if (a is bool || b is bool) return a.Equals(b);
            if (a.GetType().IsPrimitive && b.GetType().IsPrimitive)
            {
                try { return Convert.ToDouble(a) == Convert.ToDouble(b); }
                catch { return false; }
            }
            return a.Equals(b);
        }

        static string ToPsString(object o)
        {
            if (o == null) return "";
            return Convert.ToString(o, System.Globalization.CultureInfo.CurrentCulture);
        }

        static bool IsZero(object o)
        {
            if (o == null) return true;   // $null -eq 0 -> true in PowerShell
            var s = o as string;
            if (s != null) return false;  // strings are not 0
            try { return Convert.ToDouble(o) == 0d; }
            catch { return false; }
        }

        static string TypeName(object o)
        {
            return o == null ? "Null" : (o is IList ? "Array" : (o is IDictionary ? "Hashtable" : o.GetType().Name));
        }

        static IList AsList(object o)
        {
            if (o is string || o == null) return null;
            var l = o as IList;
            if (l != null) return l;
            return null;
        }

        // Comparison is strict 1:1: values are compared exactly as parsed, with no
        // implicit coercion between arrays, objects and scalars.
        static object NormalizeValue(object value, string key)
        {
            return value;
        }

        // Audit helper: reports structural fields whose parsed value is not an
        // array (next / option / global_option / config / alias).
        public static List<string> ScanNonArrayStructurals(object root, string label)
        {
            var found = new List<string>();
            Scan(root, "", label, found, 0);
            return found;
        }

        static void Scan(object value, string path, string label, List<string> found, int depth)
        {
            if (value == null || depth > 64) return;
            var arr = value as IList;
            if (arr != null && !(value is string))
            {
                foreach (var item in arr) Scan(item, path, label, found, depth + 1);
                return;
            }
            var d = value as IDictionary;
            if (d == null) return;
            foreach (var keyStr in new[] { "next", "option", "global_option", "config", "alias" })
            {
                if (!d.Contains(keyStr)) continue;
                var v = d[keyStr];
                if (v == null) continue;
                var isList = v is IList && !(v is string);
                if (!isList) found.Add(label + " > " + (path.Length > 0 ? path + " > " : "") + keyStr);
            }
            var keys = new List<object>();
            foreach (var k in d.Keys) keys.Add(k);
            foreach (var k in keys)
            {
                var ks = k as string ?? Convert.ToString(k, System.Globalization.CultureInfo.CurrentCulture);
                Scan(d[k], path.Length > 0 ? path + ">" + ks : ks, label, found, depth + 1);
            }
        }

        static void Add(List<DiffIssue> list, string path, string reason = null)
        {
            var issue = new DiffIssue { Path = path, Name = path };
            if (reason != null) issue.Reason = reason;
            list.Add(issue);
        }

        // ---- translatable text (tip / description / usage / example) ----

        static bool LikeTemplate(string s) { return s.StartsWith("{{") && s.EndsWith("}}"); }

        static void CompareTranslatableText(object baseVal, object targetVal, string path, bool identicalOk)
        {
            var baseArr = baseVal == null ? new object[0] : WrapOne(baseVal);
            var targetArr = targetVal == null ? new object[0] : WrapOne(targetVal);

            if (baseArr.Count == 0 && targetArr.Count == 0) return;
            if (baseArr.Count == 0)
            {
                if (targetArr.Count > 0) Add(S.ExtraInTarget, path);
                return;
            }

            S.TotalTips++;

            if (targetArr.Count == 0)
            {
                Add(S.MissingInTarget, path);
                return;
            }

            var hasObject = false;
            foreach (var item in baseArr) if (item is IDictionary) { hasObject = true; break; }
            if (!hasObject)
                foreach (var item in targetArr) if (item is IDictionary) { hasObject = true; break; }

            if (hasObject)
            {
                var allDescTranslated = true;
                if (baseArr.Count != targetArr.Count)
                    Add(S.SemanticMismatch, path,
                        string.Format(System.Globalization.CultureInfo.CurrentCulture, Opts.ReasonCount,
                            Opts.BaseLang, baseArr.Count, Opts.TargetLang, targetArr.Count));

                var max = Math.Min(baseArr.Count, targetArr.Count);
                for (int i = 0; i < max; i++)
                {
                    var b = baseArr[i];
                    var t = targetArr[i];
                    var bObj = b is IDictionary;
                    var tObj = t is IDictionary;
                    if (bObj != tObj)
                    {
                        Add(S.SemanticMismatch, path + " > item " + i,
                            string.Format(System.Globalization.CultureInfo.CurrentCulture, Opts.ReasonType, i));
                        continue;
                    }
                    if (bObj)
                    {
                        var bd = (IDictionary)b;
                        var td = (IDictionary)t;
                        foreach (var f in new[] { "cmd", "desc" })
                        {
                            var bf = bd.Contains(f) && bd[f] != null;
                            var tf = td.Contains(f) && td[f] != null;
                            if (bf != tf)
                                Add(S.SemanticMismatch, path + " > item " + i,
                                    string.Format(System.Globalization.CultureInfo.CurrentCulture, Opts.ReasonMissingField, i, f));
                        }
                        var bHasCmd = bd.Contains("cmd") ? bd["cmd"] : null;
                        var tHasCmd = td.Contains("cmd") ? td["cmd"] : null;
                        if (bHasCmd != null && tHasCmd != null &&
                            ToPsString(bHasCmd).Trim() != ToPsString(tHasCmd).Trim())
                            Add(S.SemanticMismatch, path + " > item " + i,
                                string.Format(System.Globalization.CultureInfo.CurrentCulture, Opts.ReasonCmdValue,
                                    i, bHasCmd, tHasCmd));
                        var bDesc = bd.Contains("desc") ? bd["desc"] : null;
                        var tDesc = td.Contains("desc") ? td["desc"] : null;
                        if (bDesc != null && tDesc != null)
                        {
                            var bs = ToPsString(bDesc).Trim();
                            var ts = ToPsString(tDesc).Trim();
                            var isTemplate = LikeTemplate(bs) && LikeTemplate(ts) && bs == ts;
                            if (!isTemplate && PsEqual(bs, ts))
                            {
                                allDescTranslated = false;
                                Add(S.Untranslated, path + " > item " + i + " > desc");
                            }
                        }
                    }
                }
                if (allDescTranslated) S.TranslatedTips++;
                return;
            }

            foreach (var item in baseArr) if (!(item is string)) return;
            foreach (var item in targetArr) if (!(item is string)) return;

            var baseSb = new System.Text.StringBuilder();
            foreach (var x in baseArr) baseSb.Append((string)x);
            var targetSb = new System.Text.StringBuilder();
            foreach (var x in targetArr) targetSb.Append((string)x);
            var baseStr = baseSb.ToString();
            var targetStr = targetSb.ToString();

            var tmpl = LikeTemplate(targetStr) && LikeTemplate(baseStr) && PsEqual(targetStr, baseStr);
            if (tmpl || !PsEqual(targetStr, baseStr) || identicalOk) S.TranslatedTips++;
            else Add(S.Untranslated, path);
        }

        static IList WrapOne(object v) { return v is IList l && !(v is string) ? l : new object[] { v }; }

        // ---- structural compare ----

        static IEnumerable AllKeys(IDictionary d)
        {
            foreach (var k in d.Keys) yield return k;
        }

        static void CompareFields(IDictionary baseObj, IDictionary targetObj, string path, bool skipValueCheck)
        {
            var seen = new HashSet<object>();
            var keys = new List<object>();
            if (baseObj != null)
                foreach (var k in baseObj.Keys) { keys.Add(k); seen.Add(k); }
            if (targetObj != null)
                foreach (var k in targetObj.Keys) if (!seen.Contains(k)) keys.Add(k);

            foreach (var key in keys)
            {
                var keyStr = ToPsString(key);
                if (path == "meta" && keyStr == "url") continue;

                var baseVal = baseObj != null && baseObj.Contains(key) ? baseObj[key] : null;
                var targetVal = targetObj != null && targetObj.Contains(key) ? targetObj[key] : null;

                var currentPath = path.Length > 0 ? path + " > " + keyStr : keyStr;
                var childSkip = skipValueCheck || (Opts.CompletionName == "psc" && keyStr != "name");

                CompareValue(baseVal, targetVal, currentPath, keyStr, childSkip);
            }
        }

        static void CompareValue(object baseValIn, object targetValIn, string path, string key, bool skipValueCheck)
        {
            if (key == "tip" || key == "description" || key == "usage" || key == "example")
            {
                CompareTranslatableText(baseValIn, targetValIn, path, key == "usage" || key == "example");
                return;
            }

            var baseVal = NormalizeValue(baseValIn, key);
            var targetVal = NormalizeValue(targetValIn, key);

            var baseType = TypeName(baseVal);
            var targetType = TypeName(targetVal);

            if (baseType == "Null" && targetType == "Null") return;

            if (baseType == "Null")
            {
                Add(S.ExtraInTarget, path);
                return;
            }
            if (targetType == "Null")
            {
                Add(S.MissingInTarget, path);
                return;
            }

            if (baseType != targetType && (baseType == "Array" || targetType == "Array" || baseType == "Hashtable" || targetType == "Hashtable"))
            {
                Add(S.TypeMismatch, path + " (" + Red + baseType + Cyan + " > " + Red + targetType + Cyan + ")");
                return;
            }

            if (key == "next" && baseType != "Array" && targetType != "Array")
            {
                if (IsZero(baseVal) || IsZero(targetVal))
                {
                    if (!PsEqual(baseVal, targetVal))
                        Add(S.SemanticMismatch, path,
                            string.Format(System.Globalization.CultureInfo.CurrentCulture, Opts.ReasonNextValue,
                                Opts.BaseLang, baseVal, Opts.TargetLang, targetVal));
                    return;
                }
            }

            if (baseType == "Array" || targetType == "Array")
            {
                var baseArr = WrapOne(baseVal);
                var targetArr = WrapOne(targetVal);

                TestDuplicates(baseArr, path, Opts.BaseLang);
                TestDuplicates(targetArr, path, Opts.TargetLang);

                var named = NamedArrayCheck(baseArr) || NamedArrayCheck(targetArr);
                if (named)
                {
                    if (baseType != targetType)
                    {
                        Add(S.TypeMismatch, path + " (" + Red + baseType + Cyan + " > " + Red + targetType + Cyan + ")");
                        return;
                    }
                    CompareNamedArray(baseArr, targetArr, path, skipValueCheck);
                }
                else
                {
                    if (skipValueCheck) return;
                    foreach (var v in baseArr)
                    {
                        var found = false;
                        foreach (var w in targetArr) if (PsEqual(v, w)) { found = true; break; }
                        if (!found) Add(S.MissingInTarget, path + " > " + ToPsString(v));
                    }
                    foreach (var v in targetArr)
                    {
                        var found = false;
                        foreach (var w in baseArr) if (PsEqual(v, w)) { found = true; break; }
                        if (!found) Add(S.ExtraInTarget, path + " > " + ToPsString(v));
                    }
                }
                return;
            }

            if (baseType == "Hashtable" && targetType == "Hashtable")
            {
                CompareFields((IDictionary)baseVal, (IDictionary)targetVal, path, skipValueCheck);
                return;
            }

            if (baseType != targetType)
            {
                Add(S.TypeMismatch, path + " (" + Red + baseType + Cyan + " > " + Red + targetType + Cyan + ")");
                return;
            }

            if (key == "name")
            {
                if (!PsEqual(baseVal, targetVal))
                    Add(S.ValueDiff, path + " (" + Red + baseVal + Cyan + " > " + Red + targetVal + Cyan + ")");
                return;
            }

            if (!skipValueCheck && !PsEqual(baseVal, targetVal))
                Add(S.ValueDiff, path + " (" + Red + baseVal + Cyan + " > " + Red + targetVal + Cyan + ")");
        }

        static bool NamedArrayCheck(IList arr)
        {
            if (arr.Count > 0)
            {
                var first = arr[0] as IDictionary;
                if (first != null && first.Contains("name")) return true;
            }
            return false;
        }

        static void TestDuplicates(IList arr, string path, string sideLabel)
        {
            if (arr == null || arr.Count < 2) return;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in arr)
            {
                var d = item as IDictionary;
                if (d == null) continue;
                if (!d.Contains("name")) continue;
                var n = ToPsString(d["name"]);
                if (!seen.Add(n))
                {
                    var currentPath = path.Length > 0 ? path + " > " + n : n;
                    Add(S.DuplicateItems, currentPath + " (" + Red + sideLabel + Cyan + ")");
                }
            }
        }

        static void CompareNamedArray(IList baseArr, IList targetArr, string path, bool skipValueCheck)
        {
            var targetByName = new Dictionary<string, object>(StringComparer.Ordinal);
            foreach (var item in targetArr)
            {
                var n = NameOfDict(item as IDictionary);
                if (n != null) targetByName[n] = item;
            }
            var baseByName = new Dictionary<string, object>(StringComparer.Ordinal);
            foreach (var item in baseArr)
            {
                var n = NameOfDict(item as IDictionary);
                if (n != null) baseByName[n] = item;
            }

            foreach (var baseItem in baseArr)
            {
                var bd = baseItem as IDictionary;
                var baseName = NameOfDict(bd);
                var currentPath = path.Length > 0 ? path + " > " + baseName : baseName;

                if (baseName != null && targetByName.ContainsKey(baseName))
                {
                    CompareFields(bd, (IDictionary)targetByName[baseName], currentPath, skipValueCheck);
                }
                else
                {
                    Add(S.MissingInTarget, currentPath);
                    if (bd != null)
                        foreach (var tKey in new[] { "tip", "description" })
                        {
                        if (!bd.Contains(tKey) || bd[tKey] == null) continue;
                        var arr = WrapOne(bd[tKey]);
                        var joined = new System.Text.StringBuilder();
                        foreach (var x in arr) joined.Append(ToPsString(x));
                        if (arr.Count > 0 && joined.ToString().Trim().Length > 0)
                            S.TotalTips++;
                        }
                }
            }
            foreach (var targetItem in targetArr)
            {
                var td = targetItem as IDictionary;
                var targetName = NameOfDict(td);
                if (targetName != null && !baseByName.ContainsKey(targetName))
                {
                    var currentPath = path.Length > 0 ? path + " > " + targetName : targetName;
                    Add(S.ExtraInTarget, currentPath);
                }
            }
        }

        static string NameOfDict(IDictionary d)
        {
            if (d == null) return null;
            if (!d.Contains("name")) return null;
            var v = d["name"];
            return v == null ? null : ToPsString(v);
        }

        // ---- per-tree usage validations ----

        static readonly Regex UsageBlockRegex =
            new Regex("^([^\\s,|<=\\[|]+(?:\\s*[,|]\\s*[^\\s,|<=\\[|]+)*)");

        static readonly Regex PlaceholderRegex = new Regex("<[^<>]*>");

        static void ValidateUsageFormat(string line, string path, bool isOption)
        {
            var u = line.Substring(2).Trim();
            var m = UsageBlockRegex.Match(u);
            if (!m.Success) return;
            var block = m.Value;
            if (block.IndexOf(',') < 0 && block.IndexOf('|') < 0) return;

            var parts = block.Split(',', '|');
            var forms = new List<string>();
            foreach (var p in parts)
            {
                var t = p.Trim();
                if (t.Length > 0) forms.Add(t);
            }
            var hasPipe = block.IndexOf('|') >= 0;
            var hasComma = block.IndexOf(',') >= 0;
            if (isOption && hasPipe && !hasComma) Add(S.UsageSeparator, path);
            else if (!isOption && hasComma && !hasPipe) Add(S.UsageSeparator, path);
            for (int i = 0; i < forms.Count - 1; i++)
            {
                if (forms[i].Length > forms[i + 1].Length)
                {
                    Add(S.UsageOrder, path);
                    break;
                }
            }
        }

        static void ValidateItemUsage(IDictionary item, string path, bool isOption, bool deep)
        {
            var name = NameOfDict(item);
            var aliasRaw = item.Contains("alias") ? item["alias"] : null;
            var hasAlias = false;
            if (aliasRaw != null)
            {
                var al = WrapOne(aliasRaw);
                if (al.Count > 0) hasAlias = true;
            }
            var hasNext = item.Contains("next") && item["next"] != null;

            var needsUsage = hasAlias;

            var hasUsage = false;
            var useless = false;
            var optionLike = isOption || (name != null && name.StartsWith("-"));

            if (item.Contains("usage") && item["usage"] != null)
            {
                var usageArr = WrapOne(item["usage"]);
                foreach (var uo in usageArr)
                {
                    if (uo is string us)
                    {
                        ValidateUsageFormat("U: " + us, path, optionLike);
                        if (!hasUsage)
                        {
                            hasUsage = true;
                            if (us.Trim() == name || (name != null && PsEqual(us.Trim(), name))) useless = true;
                        }
                    }
                    else if (uo is IDictionary ud)
                    {
                        var cmdRaw = ud.Contains("cmd") ? ud["cmd"] : null;
                        var cmd = cmdRaw == null ? "" : ToPsString(cmdRaw);
                        if (cmd.Length > 0)
                        {
                            ValidateUsageFormat("U: " + cmd, path, optionLike);
                            if (!hasUsage)
                            {
                                hasUsage = true;
                                if (cmd.Trim() == name || (name != null && PsEqual(cmd.Trim(), name))) useless = true;
                            }
                        }
                    }
                }
            }

            if (needsUsage && !hasUsage) Add(S.MissingUsage, path, name);
            else if (hasUsage && useless)
            {
                if (!hasAlias && !hasNext) Add(S.MeaninglessUsage, path, name);
                else Add(S.UsageTooSimple, path, name);
            }

            if (optionLike && hasUsage && !hasNext)
            {
                foreach (var uo in WrapOne(item["usage"]))
                {
                    string s = null;
                    if (uo is string us) s = us;
                    else if (uo is IDictionary ud && ud.Contains("cmd") && ud["cmd"] != null) s = ToPsString(ud["cmd"]);
                    if (s == null) continue;
                    var beforeHash = s.Split('#')[0];
                    if (PlaceholderRegex.IsMatch(beforeHash))
                    {
                        Add(S.OptionMissingNext, path, name);
                        break;
                    }
                }
            }

            if (deep && hasUsage)
            {
                foreach (var uo in WrapOne(item["usage"]))
                {
                    string s = null;
                    if (uo is string us) s = us;
                    else if (uo is IDictionary ud && ud.Contains("cmd") && ud["cmd"] != null) s = ToPsString(ud["cmd"]);
                    if (s == null) continue;
                    if (s.StartsWith(Opts.CompletionName + " ", StringComparison.CurrentCulture))
                    {
                        Add(S.UsageRootPrefix, path, name);
                        break;
                    }
                }
            }
        }

        static void ValidateAllTips(IDictionary content, string basePath, bool isOption, bool isCommand)
        {
            var name = NameOfDict(content);
            if (name != null) ValidateItemUsage(content, basePath, isOption, basePath.Contains(" > "));

            if (isCommand && content.Contains("next"))
            {
                var nextVal = content["next"];
                if (nextVal != null)
                {
                    var nl = nextVal as IList;
                    if (nl != null && !(nextVal is string) && nl.Count == 0)
                        Add(S.ForbiddenEmptyNext, basePath, name);
                }
            }

            if (content.Contains("next") && content["next"] is IList nextList)
            {
                foreach (var sub in nextList)
                {
                    var sd = sub as IDictionary;
                    if (sd == null) continue;
                    var subName = NameOfDict(sd);
                    if (subName == null) continue;
                    ValidateAllTips(sd, basePath.Length > 0 ? basePath + " > " + subName : subName, false, true);
                }
            }

            if (content.Contains("option") && content["option"] is IList optionList)
            {
                foreach (var opt in optionList)
                {
                    var od = opt as IDictionary;
                    if (od == null || NameOfDict(od) == null) continue;
                    var optName = NameOfDict(od);
                    ValidateAllTips(od, basePath.Length > 0 ? basePath + " > option > " + optName : "option > " + optName, true, false);
                }
            }

            if (content.Contains("global_option") && content["global_option"] is IList goList)
            {
                foreach (var opt in goList)
                {
                    var od = opt as IDictionary;
                    if (od == null || NameOfDict(od) == null) continue;
                    ValidateAllTips(od, "global_option > " + NameOfDict(od), true, false);
                }
            }
        }

        // ---- global option duplicate detection ----

        static bool SubtreeEqual(object a, object b)
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            var da = a as IDictionary;
            var db = b as IDictionary;
            if (da != null && db != null)
            {
                if (da.Count != db.Count) return false;
                foreach (var k in da.Keys)
                    if (!db.Contains(k) || !SubtreeEqual(da[k], db[k])) return false;
                return true;
            }
            var la = a as IList;
            var lb = b as IList;
            if (la != null && lb != null)
            {
                if (la.Count != lb.Count) return false;
                for (int i = 0; i < la.Count; i++)
                    if (!SubtreeEqual(la[i], lb[i])) return false;
                return true;
            }
            return PsEqual(a, b);
        }

        static List<KeyValuePair<string, IDictionary>> GlobalOptions;

        static void TestGlobalDuplicate(IDictionary opt, string path)
        {
            var optName = NameOfDict(opt);
            if (optName == null) return;
            foreach (var g in GlobalOptions)
            {
                if (g.Key == optName && SubtreeEqual(opt, g.Value))
                {
                    Add(S.DuplicateOptions, path + " > " + optName, optName);
                    return;
                }
            }
        }

        static void CheckOptionDuplicates(IDictionary node, string path)
        {
            if (node.Contains("option") && node["option"] is IList ol)
                foreach (var opt in ol)
                {
                    var od = opt as IDictionary;
                    if (od != null) TestGlobalDuplicate(od, path);
                }

            if (node.Contains("next") && node["next"] is IList nl)
                foreach (var sub in nl)
                {
                    var sd = sub as IDictionary;
                    var n = NameOfDict(sd);
                    if (n != null) CheckOptionDuplicates(sd, path + " > " + n);
                }
        }

        static void ValidateOptions(IDictionary content)
        {
            GlobalOptions = new List<KeyValuePair<string, IDictionary>>();
            if (content.Contains("global_option") && content["global_option"] is IList gol)
                foreach (var opt in gol)
                {
                    var od = opt as IDictionary;
                    var n = NameOfDict(od);
                    if (n != null) GlobalOptions.Add(new KeyValuePair<string, IDictionary>(n, od));
                }
            if (GlobalOptions.Count == 0) return;

            if (content.Contains("option") && content["option"] is IList ol)
                foreach (var opt in ol)
                {
                    var od = opt as IDictionary;
                    if (od != null) TestGlobalDuplicate(od, "option");
                }

            if (content.Contains("next") && content["next"] is IList nl)
                foreach (var sub in nl)
                {
                    var sd = sub as IDictionary;
                    var n = NameOfDict(sd);
                    if (n != null) CheckOptionDuplicates(sd, n);
                }
        }
    }
}
