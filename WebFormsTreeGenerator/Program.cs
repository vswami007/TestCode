using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;

class Program
{
    static void Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.WriteLine("Usage: dotnet run <path-to-cs-file> [method-name]");
            Console.WriteLine("Example: dotnet run TicketEntry.aspx.cs Page_Load");
            Console.WriteLine("If method-name not provided, analyzes Page_Load and all event handlers");
            return;
        }

        string filePath = args[0];
        string targetMethod = args.Length > 1 ? args[1] : null;

        if (!File.Exists(filePath))
        {
            Console.WriteLine($"Error: File not found: {filePath}");
            return;
        }

        try
        {
            string code = File.ReadAllText(filePath);
            var tree = CSharpSyntaxTree.ParseText(code);
            var root = tree.GetCompilationUnitRoot();

            var generator = new MermaidFlowGenerator();
            var mermaid = generator.GenerateFlow(root, targetMethod);

            string outputPath = Path.ChangeExtension(filePath, ".flow.md");
            File.WriteAllText(outputPath, mermaid);

            Console.WriteLine($"✓ Flow diagram generated: {outputPath}");
            Console.WriteLine($"✓ Open in VS Code or any Markdown viewer with Mermaid support");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
        }
    }
}

class MermaidFlowGenerator
{
    private StringBuilder _mermaid;
    private int _nodeCounter;
    private HashSet<string> _processedMethods;
    private int _maxDepth = 2; // Prevent infinite recursion

    public string GenerateFlow(CompilationUnitSyntax root, string targetMethod = null)
    {
        _mermaid = new StringBuilder();
        _nodeCounter = 0;
        _processedMethods = new HashSet<string>();

        _mermaid.AppendLine("# Code Flow Diagram");
        _mermaid.AppendLine();
        _mermaid.AppendLine("```mermaid");
        _mermaid.AppendLine("graph TD");

        var classDeclaration = root.DescendantNodes()
            .OfType<ClassDeclarationSyntax>()
            .FirstOrDefault();

        if (classDeclaration == null)
        {
            _mermaid.AppendLine("    A[No class found]");
            _mermaid.AppendLine("```");
            return _mermaid.ToString();
        }

        var methods = classDeclaration.DescendantNodes().OfType<MethodDeclarationSyntax>();

        if (targetMethod != null)
        {
            // Analyze specific method
            var method = methods.FirstOrDefault(m => m.Identifier.Text == targetMethod);
            if (method != null)
            {
                AnalyzeMethod(method, classDeclaration);
            }
            else
            {
                _mermaid.AppendLine($"    A[Method '{targetMethod}' not found]");
            }
        }
        else
        {
            // Analyze Page_Load first
            var pageLoad = methods.FirstOrDefault(m => m.Identifier.Text == "Page_Load");
            if (pageLoad != null)
            {
                AnalyzeMethod(pageLoad, classDeclaration);
                _mermaid.AppendLine();
            }

            // Then analyze event handlers
            var eventHandlers = methods.Where(m =>
                m.Identifier.Text.EndsWith("_Click") ||
                m.Identifier.Text.EndsWith("_Changed") ||
                m.Identifier.Text.EndsWith("_SelectedIndexChanged") ||
                m.Identifier.Text.EndsWith("_CheckedChanged"));

            foreach (var handler in eventHandlers.Take(10)) // Limit to avoid huge diagrams
            {
                _mermaid.AppendLine();
                AnalyzeMethod(handler, classDeclaration);
            }
        }

        _mermaid.AppendLine("```");
        return _mermaid.ToString();
    }

    private void AnalyzeMethod(MethodDeclarationSyntax method, ClassDeclarationSyntax classDecl)
    {
        if (_processedMethods.Contains(method.Identifier.Text))
            return;

        _processedMethods.Add(method.Identifier.Text);

        string startNode = GetNextNodeId();
        _mermaid.AppendLine($"    {startNode}([{method.Identifier.Text}])");
        _mermaid.AppendLine($"    style {startNode} fill:#e1f5ff,stroke:#01579b,stroke-width:2px");

        if (method.Body != null)
        {
            ProcessStatements(method.Body.Statements, startNode, classDecl, 0);
        }
    }

    private string ProcessStatements(SyntaxList<StatementSyntax> statements, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        string currentNode = parentNode;

        foreach (var statement in statements)
        {
            currentNode = ProcessStatement(statement, currentNode, classDecl, depth);
        }

        return currentNode;
    }

    private string ProcessStatement(StatementSyntax statement, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        if (depth > 10) // Prevent stack overflow on deeply nested code
        {
            string deepNode = GetNextNodeId();
            _mermaid.AppendLine($"    {parentNode} --> {deepNode}[...]");
            return deepNode;
        }

        switch (statement)
        {
            case IfStatementSyntax ifStmt:
                return ProcessIfStatement(ifStmt, parentNode, classDecl, depth);

            case ForStatementSyntax forStmt:
                return ProcessForLoop(forStmt, parentNode, classDecl, depth);

            case ForEachStatementSyntax foreachStmt:
                return ProcessForEachLoop(foreachStmt, parentNode, classDecl, depth);

            case WhileStatementSyntax whileStmt:
                return ProcessWhileLoop(whileStmt, parentNode, classDecl, depth);

            case SwitchStatementSyntax switchStmt:
                return ProcessSwitchStatement(switchStmt, parentNode, classDecl, depth);

            case TryStatementSyntax tryStmt:
                return ProcessTryStatement(tryStmt, parentNode, classDecl, depth);

            case ReturnStatementSyntax returnStmt:
                return ProcessReturnStatement(returnStmt, parentNode);

            case ExpressionStatementSyntax exprStmt:
                return ProcessExpressionStatement(exprStmt, parentNode, classDecl, depth);

            case LocalDeclarationStatementSyntax localDecl:
                return ProcessLocalDeclaration(localDecl, parentNode);

            case BlockSyntax block:
                return ProcessStatements(block.Statements, parentNode, classDecl, depth);

            default:
                return ProcessGenericStatement(statement, parentNode);
        }
    }

    private string ProcessIfStatement(IfStatementSyntax ifStmt, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        string conditionNode = GetNextNodeId();
        string condition = CleanCondition(ifStmt.Condition.ToString());

        _mermaid.AppendLine($"    {parentNode} --> {conditionNode}{{{condition}}}");
        _mermaid.AppendLine($"    style {conditionNode} fill:#fff9c4,stroke:#f57f17");

        // True branch
        string trueNode = GetNextNodeId();
        _mermaid.AppendLine($"    {conditionNode} -->|Yes| {trueNode}[ ]");
        string trueEnd = ProcessStatement(ifStmt.Statement, trueNode, classDecl, depth + 1);

        // False branch
        string falseEnd = conditionNode;
        if (ifStmt.Else != null)
        {
            string falseNode = GetNextNodeId();
            _mermaid.AppendLine($"    {conditionNode} -->|No| {falseNode}[ ]");
            falseEnd = ProcessStatement(ifStmt.Else.Statement, falseNode, classDecl, depth + 1);
        }
        else
        {
            string skipNode = GetNextNodeId();
            _mermaid.AppendLine($"    {conditionNode} -->|No| {skipNode}[ ]");
            falseEnd = skipNode;
        }

        // Merge
        string mergeNode = GetNextNodeId();
        _mermaid.AppendLine($"    {trueEnd} --> {mergeNode}[ ]");
        if (falseEnd != conditionNode)
        {
            _mermaid.AppendLine($"    {falseEnd} --> {mergeNode}");
        }

        return mergeNode;
    }

    private string ProcessForLoop(ForStatementSyntax forStmt, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        string loopNode = GetNextNodeId();
        string condition = forStmt.Condition?.ToString() ?? "condition";
        condition = CleanCondition(condition);

        _mermaid.AppendLine($"    {parentNode} --> {loopNode}{{For: {condition}}}");
        _mermaid.AppendLine($"    style {loopNode} fill:#e8f5e9,stroke:#2e7d32");

        string bodyNode = GetNextNodeId();
        _mermaid.AppendLine($"    {loopNode} -->|Loop| {bodyNode}[ ]");

        string bodyEnd = ProcessStatement(forStmt.Statement, bodyNode, classDecl, depth + 1);
        _mermaid.AppendLine($"    {bodyEnd} --> {loopNode}");

        string exitNode = GetNextNodeId();
        _mermaid.AppendLine($"    {loopNode} -->|Exit| {exitNode}[ ]");

        return exitNode;
    }

    private string ProcessForEachLoop(ForEachStatementSyntax foreachStmt, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        string loopNode = GetNextNodeId();
        string expression = CleanCondition(foreachStmt.Expression.ToString());

        _mermaid.AppendLine($"    {parentNode} --> {loopNode}{{ForEach: {expression}}}");
        _mermaid.AppendLine($"    style {loopNode} fill:#e8f5e9,stroke:#2e7d32");

        string bodyNode = GetNextNodeId();
        _mermaid.AppendLine($"    {loopNode} -->|Each| {bodyNode}[ ]");

        string bodyEnd = ProcessStatement(foreachStmt.Statement, bodyNode, classDecl, depth + 1);
        _mermaid.AppendLine($"    {bodyEnd} --> {loopNode}");

        string exitNode = GetNextNodeId();
        _mermaid.AppendLine($"    {loopNode} -->|Done| {exitNode}[ ]");

        return exitNode;
    }

    private string ProcessWhileLoop(WhileStatementSyntax whileStmt, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        string loopNode = GetNextNodeId();
        string condition = CleanCondition(whileStmt.Condition.ToString());

        _mermaid.AppendLine($"    {parentNode} --> {loopNode}{{While: {condition}}}");

        string bodyNode = GetNextNodeId();
        _mermaid.AppendLine($"    {loopNode} -->|True| {bodyNode}[ ]");

        string bodyEnd = ProcessStatement(whileStmt.Statement, bodyNode, classDecl, depth + 1);
        _mermaid.AppendLine($"    {bodyEnd} --> {loopNode}");

        string exitNode = GetNextNodeId();
        _mermaid.AppendLine($"    {loopNode} -->|False| {exitNode}[ ]");

        return exitNode;
    }

    private string ProcessSwitchStatement(SwitchStatementSyntax switchStmt, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        string switchNode = GetNextNodeId();
        string expression = CleanCondition(switchStmt.Expression.ToString());

        _mermaid.AppendLine($"    {parentNode} --> {switchNode}{{Switch: {expression}}}");

        var caseEnds = new List<string>();

        foreach (var section in switchStmt.Sections)
        {
            foreach (var label in section.Labels)
            {
                string caseNode = GetNextNodeId();
                string caseLabel = label is CaseSwitchLabelSyntax caseSwitch
                    ? CleanCondition(caseSwitch.Value.ToString())
                    : "default";

                _mermaid.AppendLine($"    {switchNode} -->|{caseLabel}| {caseNode}[ ]");
                string caseEnd = ProcessStatements(section.Statements, caseNode, classDecl, depth + 1);
                caseEnds.Add(caseEnd);
            }
        }

        string mergeNode = GetNextNodeId();
        foreach (var end in caseEnds)
        {
            _mermaid.AppendLine($"    {end} --> {mergeNode}[ ]");
        }

        return mergeNode;
    }

    private string ProcessTryStatement(TryStatementSyntax tryStmt, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        string tryNode = GetNextNodeId();
        _mermaid.AppendLine($"    {parentNode} --> {tryNode}[Try Block]");
        _mermaid.AppendLine($"    style {tryNode} fill:#ffebee,stroke:#c62828");

        string tryEnd = ProcessStatement(tryStmt.Block, tryNode, classDecl, depth + 1);

        var catchEnds = new List<string>();
        catchEnds.Add(tryEnd);

        foreach (var catchClause in tryStmt.Catches)
        {
            string catchNode = GetNextNodeId();
            string exceptionType = catchClause.Declaration?.Type.ToString() ?? "Exception";
            _mermaid.AppendLine($"    {tryNode} -.->|Catch: {exceptionType}| {catchNode}[Catch]");

            string catchEnd = ProcessStatement(catchClause.Block, catchNode, classDecl, depth + 1);
            catchEnds.Add(catchEnd);
        }

        if (tryStmt.Finally != null)
        {
            string finallyNode = GetNextNodeId();
            _mermaid.AppendLine($"    {tryNode} --> {finallyNode}[Finally]");

            foreach (var end in catchEnds)
            {
                _mermaid.AppendLine($"    {end} --> {finallyNode}");
            }

            return ProcessStatement(tryStmt.Finally.Block, finallyNode, classDecl, depth + 1);
        }

        string mergeNode = GetNextNodeId();
        foreach (var end in catchEnds)
        {
            _mermaid.AppendLine($"    {end} --> {mergeNode}[ ]");
        }

        return mergeNode;
    }

    private string ProcessReturnStatement(ReturnStatementSyntax returnStmt, string parentNode)
    {
        string returnNode = GetNextNodeId();
        string returnValue = returnStmt.Expression != null
            ? CleanCondition(returnStmt.Expression.ToString())
            : "void";

        _mermaid.AppendLine($"    {parentNode} --> {returnNode}([Return: {returnValue}])");
        _mermaid.AppendLine($"    style {returnNode} fill:#fce4ec,stroke:#880e4f");

        return returnNode;
    }

    private string ProcessExpressionStatement(ExpressionStatementSyntax exprStmt, string parentNode, ClassDeclarationSyntax classDecl, int depth)
    {
        if (exprStmt.Expression is InvocationExpressionSyntax invocation)
        {
            string methodName = GetMethodName(invocation);
            string nodeId = GetNextNodeId();

            // Check if it's a SOAP/external service call
            if (methodName.Contains(".") || IsServiceCall(invocation))
            {
                _mermaid.AppendLine($"    {parentNode} --> {nodeId}[[Service: {methodName}]]");
                _mermaid.AppendLine($"    style {nodeId} fill:#f3e5f5,stroke:#4a148c");
            }
            else
            {
                _mermaid.AppendLine($"    {parentNode} --> {nodeId}[{methodName}#40;#41;]");
            }

            return nodeId;
        }

        // Assignment or other expression
        string label = CleanLabel(exprStmt.Expression.ToString());
        string exprNode = GetNextNodeId();
        _mermaid.AppendLine($"    {parentNode} --> {exprNode}[{label}]");

        return exprNode;
    }

    private string ProcessLocalDeclaration(LocalDeclarationStatementSyntax localDecl, string parentNode)
    {
        string label = CleanLabel(localDecl.Declaration.ToString());
        string declNode = GetNextNodeId();
        _mermaid.AppendLine($"    {parentNode} --> {declNode}[{label}]");

        return declNode;
    }

    private string ProcessGenericStatement(StatementSyntax statement, string parentNode)
    {
        string nodeId = GetNextNodeId();
        string label = statement.GetType().Name.Replace("Syntax", "").Replace("Statement", "");
        _mermaid.AppendLine($"    {parentNode} --> {nodeId}[{label}]");

        return nodeId;
    }

    private string GetMethodName(InvocationExpressionSyntax invocation)
    {
        if (invocation.Expression is MemberAccessExpressionSyntax memberAccess)
        {
            return memberAccess.Name.ToString();
        }
        else if (invocation.Expression is IdentifierNameSyntax identifier)
        {
            return identifier.Identifier.Text;
        }
        return invocation.Expression.ToString();
    }

    private bool IsServiceCall(InvocationExpressionSyntax invocation)
    {
        var methodName = GetMethodName(invocation);
        return methodName.Contains("Service") || 
               methodName.Contains("Client") || 
               methodName.Contains("Proxy") ||
               invocation.Expression.ToString().Contains("new ");
    }

    

    private string CleanLabel(string label, int maxLength = 40)
    {
    label = label.Replace("\"", "'")
                 .Replace("\n", " ")
                 .Replace("\r", "")
                 .Replace("  ", " ")
                 .Replace("(", "#40;")   // Add this
                 .Replace(")", "#41;")   // Add this
                 .Replace("{", "#123;")  // Add this
                 .Replace("}", "#125;")  // Add this
                 .Replace("[", "#91;")   // Add this
                 .Replace("]", "#93;")   // Add this
                 .Replace("<", "#60;")   // Add this
                 .Replace(">", "#62;")   // Add this
                 .Trim();

    if (label.Length > maxLength)
    {
        label = label.Substring(0, maxLength - 3) + "...";
    }

    return label;
    }
private string CleanCondition(string condition)
    {
    return CleanLabel(condition, 60);
    }

    private string GetNextNodeId()
    {
        return $"N{_nodeCounter++}";
    }
}