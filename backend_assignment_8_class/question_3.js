

// Store employee data in an array
let employeeInfo = [
    { name: 'Sara', department: 'HR', salary: 70000 },
    { name: 'Ahmed', department: 'IT', salary: 95000 },
    { name: 'Ayesha', department: 'Finance', salary: 85000 }
];

// Find employees who belong to the IT department
let employees = employeeInfo.filter(employee => employee.department == "IT");
console.log("IT Employees:", employees);

// Find the first employee whose salary is greater than 90000
let employeesList = employeeInfo.find(employee => employee.salary > 90000);
console.log("First high-salary employee:", employeesList);

// Create a new array containing only employee names
let names = employeeInfo.map(employee => employee.name);
console.log("Employee Names:", names);

// Calculate the total salary of all employees
let calculateSalary = employeeInfo.reduce((sum, employee) => {
    return sum + employee.salary;
}, 0);
console.log("Total Salary:", calculateSalary);
